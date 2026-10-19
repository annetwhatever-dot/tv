"""Local, phone-friendly OLED light controller for Anna's LG C1."""
import asyncio
import ipaddress
import json
import os
from pathlib import Path
import socket
import subprocess
import time
from urllib.parse import urlparse
import xml.etree.ElementTree as ET

from aiohttp import ClientSession, web
from bscpylgtv import WebOsClient

ROOT = Path(__file__).resolve().parent
STATE = ROOT / '.state'
STATE.mkdir(mode=0o700, exist_ok=True)
CONFIG = STATE / 'tv.json'
PORT = int(os.environ.get('PORT', '8765'))


def private_ip(value):
    try:
        ip = ipaddress.IPv4Address(value)
    except (ValueError, TypeError):
        raise ValueError('Enter the TV’s local IPv4 address, for example 192.168.0.100.')
    if not ip.is_private or ip.is_loopback or ip.is_unspecified or ip.is_multicast or ip.is_link_local:
        raise ValueError('Use the TV’s address on your home network.')
    return str(ip)


def physical_networks():
    result = []
    try:
        output = subprocess.check_output(['networksetup', '-listallhardwareports'], text=True)
        for block in output.split('\n\n'):
            if 'Wi-Fi' not in block and 'Ethernet' not in block:
                continue
            for line in block.splitlines():
                if line.startswith('Device: '):
                    name = line.split(': ', 1)[1]
                    try:
                        ip = subprocess.check_output(['ipconfig', 'getifaddr', name], text=True, stderr=subprocess.DEVNULL).strip()
                        mask = subprocess.check_output(['ipconfig', 'getoption', name, 'subnet_mask'], text=True, stderr=subprocess.DEVNULL).strip() or '255.255.255.0'
                        result.append((private_ip(ip), ipaddress.IPv4Network(f'{ip}/{mask}', strict=False)))
                    except (ValueError, subprocess.CalledProcessError):
                        pass
    except (OSError, subprocess.CalledProcessError):
        pass
    return result


def ssdp_search(local_ip):
    locations = set()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(0.4)
        sock.bind((local_ip, 0))
        query = ('M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n'
                 'MAN: "ssdp:discover"\r\nMX: 2\r\n'
                 'ST: urn:lge-com:service:webos-second-screen:1\r\n\r\n')
        sock.sendto(query.encode(), ('239.255.255.250', 1900))
        until = time.monotonic() + 3
        while time.monotonic() < until:
            try:
                message, _ = sock.recvfrom(8192)
                for line in message.decode(errors='replace').splitlines():
                    if line.lower().startswith('location:'):
                        url = line.split(':', 1)[1].strip()
                        parsed = urlparse(url)
                        if parsed.scheme == 'http':
                            private_ip(parsed.hostname)
                            locations.add(url)
            except socket.timeout:
                pass
            except ValueError:
                pass
    return locations


async def discover_tvs():
    networks = await asyncio.to_thread(physical_networks)
    locations = await asyncio.gather(*(asyncio.to_thread(ssdp_search, ip) for ip, _ in networks), return_exceptions=True)
    found = {}
    async with ClientSession() as session:
        for group in locations:
            if isinstance(group, Exception):
                continue
            for url in group:
                ip = urlparse(url).hostname
                try:
                    async with session.get(url, timeout=2, allow_redirects=False) as response:
                        root = ET.fromstring((await response.text())[:100000])
                    fields = {el.tag.split('}')[-1]: el.text for el in root.iter()}
                    found[ip] = {'ip': ip, 'name': fields.get('friendlyName') or 'LG TV', 'model': fields.get('modelName') or 'webOS TV'}
                except Exception:
                    pass

        # Discovery is sometimes filtered by routers. Probe only the Mac's physical LAN.
        if not found:
            semaphore = asyncio.Semaphore(48)

            async def probe(ip):
                async with semaphore:
                    for port in (3001, 3000):
                        try:
                            reader, writer = await asyncio.wait_for(asyncio.open_connection(ip, port), 0.35)
                            writer.close()
                            await writer.wait_closed()
                        except Exception:
                            continue
                        try:
                            scheme = 'wss' if port == 3001 else 'ws'
                            async with session.ws_connect(f'{scheme}://{ip}:{port}', ssl=False, timeout=2) as ws:
                                await ws.send_json({'id': 'identify', 'type': 'hello'})
                                message = await asyncio.wait_for(ws.receive_json(), 2)
                                payload = message.get('payload', {})
                                if message.get('type') == 'hello' and ('deviceUUID' in payload or 'productName' in payload):
                                    found[ip] = {'ip': ip, 'name': 'LG TV', 'model': payload.get('productName', 'webOS TV')}
                        except Exception:
                            pass
                        break

            hosts = {str(host) for own, net in networks if net.num_addresses <= 1024 for host in net.hosts() if str(host) != own}
            await asyncio.gather(*(probe(ip) for ip in hosts))
    return list(found.values())


class Controller:
    def __init__(self):
        try:
            self.config = json.loads(CONFIG.read_text())
        except (OSError, ValueError):
            self.config = {}
        self.client = None
        self.lock = asyncio.Lock()
        self.pairing = False
        self.error = None
        self.level = None
        self.mode = None
        self.verified = False
        self.updated = None

    def save(self):
        temporary = CONFIG.with_suffix('.tmp')
        temporary.write_text(json.dumps(self.config))
        temporary.chmod(0o600)
        temporary.replace(CONFIG)

    async def disconnect(self):
        if self.client:
            await self.client.disconnect()
        self.client = None

    async def connect(self, ip):
        async with self.lock:
            await self.disconnect()
            self.pairing = True
            self.error = None
            self.level = None
            self.mode = None
            self.verified = False
            try:
                # websockets 15 also reads macOS proxy settings; TV traffic stays on LAN.
                bypass = {item.strip() for item in (os.environ.get('NO_PROXY', '') + ',' + os.environ.get('no_proxy', '')).split(',') if item.strip()}
                bypass.add(ip)
                os.environ['NO_PROXY'] = os.environ['no_proxy'] = ','.join(sorted(bypass))
                # Prefer TLS; older firmware may offer only the non-TLS LAN endpoint.
                ssl_available = True
                try:
                    _, writer = await asyncio.wait_for(asyncio.open_connection(ip, 3001), 2)
                    writer.close()
                    await writer.wait_closed()
                except Exception:
                    ssl_available = False
                self.client = await WebOsClient.create(
                    ip, key_file_path=str(STATE / 'pairing.sqlite'), states=[],
                    without_ssl=not ssl_available, timeout_connect=3, connect_retry_attempts=1,
                )
                await asyncio.wait_for(self.client.connect(), 65)
                self.config = {'ip': ip}
                self.save()
                await self.read()
            except Exception as exc:
                await self.disconnect()
                self.error = friendly_error(exc)
                raise RuntimeError(self.error)
            finally:
                self.pairing = False

    async def read(self):
        try:
            # C1 firmware rejects pictureMode here and fails the entire request.
            settings = await asyncio.wait_for(self.client.get_picture_settings(['backlight']), 5)
            value = settings.get('backlight')
            self.level = int(value) if value is not None else None
            self.verified = self.level is not None
            self.updated = time.time()
            self.error = None
        except Exception:
            self.verified = False
            self.error = 'Connected, but this TV did not share its current brightness. You can still try a preset.'

    async def refresh(self):
        async with self.lock:
            if self.client and self.client.is_connected() and not self.pairing:
                await self.read()

    async def set_level(self, value):
        async with self.lock:
            if not self.client or not self.client.is_connected():
                raise RuntimeError('The TV is disconnected. Switch it on and reconnect.')
            try:
                try:
                    await asyncio.wait_for(self.client.set_system_settings('picture', {'backlight': value}), 5)
                except Exception:
                    # Supported library path for models that reject direct writes.
                    await asyncio.wait_for(self.client.set_settings('picture', {'backlight': value}), 5)
                await asyncio.sleep(0.3)
                await self.read()
                if self.verified and self.level != value:
                    raise RuntimeError('The TV kept its previous brightness. Check whether Energy Saving is limiting OLED Pixel Brightness.')
                if not self.verified:
                    self.error = 'Sent to TV; its current brightness could not be confirmed.'
            except Exception as exc:
                self.error = friendly_error(exc)
                raise RuntimeError(self.error)

    def status(self):
        return {
            'connected': bool(self.client and self.client.is_connected() and not self.pairing),
            'pairing': self.pairing, 'ip': self.config.get('ip'), 'brightness': self.level,
            'mode': self.mode, 'verified': self.verified, 'message': self.error,
            'updated': self.updated,
        }


def friendly_error(exc):
    if isinstance(exc, (asyncio.TimeoutError, TimeoutError)):
        return 'Connection timed out. Keep the TV on, use the same home network, and accept the request on the TV.'
    if isinstance(exc, OSError):
        return 'Cannot reach the TV. Check its network connection and IP address.'
    return str(exc) or 'The TV did not respond. Try reconnecting.'


controller = Controller()


@web.middleware
async def guard(request, handler):
    if request.path.startswith('/api/') and request.method != 'GET':
        origin = request.headers.get('Origin')
        if request.headers.get('X-TV-Control') != '1' or (origin and origin != f'{request.scheme}://{request.host}'):
            return web.json_response({'error': 'Open the controller directly to use it.'}, status=403)
    try:
        response = await handler(request)
    except (ValueError, json.JSONDecodeError) as exc:
        response = web.json_response({'error': str(exc)}, status=400)
    except RuntimeError as exc:
        response = web.json_response({'error': str(exc), **controller.status()}, status=502)
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['Content-Security-Policy'] = "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'"
    return response


async def index(request):
    return web.FileResponse(ROOT / 'public' / 'index.html')


async def status(request):
    if request.query.get('refresh') == '1' and not controller.pairing:
        await controller.refresh()
    return web.json_response(controller.status())


async def discovery(request):
    return web.json_response({'tvs': await discover_tvs()})


async def connect(request):
    data = await request.json()
    ip = private_ip(data.get('ip', controller.config.get('ip')))
    if controller.pairing:
        return web.json_response({'error': 'A connection request is already open. Check the TV.'}, status=409)
    await controller.connect(ip)
    return web.json_response(controller.status())


async def brightness(request):
    data = await request.json()
    value = data.get('brightness')
    if type(value) is not int or not 0 <= value <= 100:
        raise ValueError('Brightness must be a whole number between 0 and 100.')
    await controller.set_level(value)
    return web.json_response(controller.status())


async def startup(app):
    async def restore():
        if controller.config.get('ip'):
            try:
                await controller.connect(private_ip(controller.config['ip']))
            except (ValueError, RuntimeError):
                pass
    app['restore'] = asyncio.create_task(restore())


async def cleanup(app):
    app['restore'].cancel()
    await asyncio.gather(app['restore'], return_exceptions=True)
    await controller.disconnect()


def make_app():
    app = web.Application(middlewares=[guard], client_max_size=4096)
    app.add_routes([
        web.get('/', index), web.get('/api/status', status),
        web.post('/api/discover', discovery), web.post('/api/connect', connect),
        web.post('/api/brightness', brightness),
    ])
    app.router.add_static('/assets/', ROOT / 'public')
    app.on_startup.append(startup)
    app.on_cleanup.append(cleanup)
    return app


if __name__ == '__main__':
    web.run_app(make_app(), host='0.0.0.0', port=PORT, print=lambda message: print(message, flush=True))
