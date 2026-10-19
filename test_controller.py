"""Control behavior tests. No network or physical TV changes."""
import asyncio
import unittest
from unittest.mock import AsyncMock

from server import Controller, private_ip


class BrightnessTests(unittest.IsolatedAsyncioTestCase):
    def make_controller(self):
        controller = Controller()
        client = AsyncMock()
        client.is_connected = lambda: True
        client.get_picture_settings.return_value = {'backlight': '45', 'pictureMode': 'expert2'}
        controller.client = client
        return controller, client

    async def test_readback_verifies_changed_value(self):
        controller, client = self.make_controller()
        await controller.set_level(45)
        client.set_system_settings.assert_awaited_once_with('picture', {'backlight': 45})
        client.set_settings.assert_not_awaited()
        self.assertEqual(controller.level, 45)
        self.assertTrue(controller.verified)

    async def test_read_does_not_request_unsupported_picture_mode(self):
        controller, client = self.make_controller()

        async def read_allowed_keys(keys):
            if keys != ['backlight']:
                raise RuntimeError('Some keys are not allowed for the request. ( pictureMode )')
            return {'backlight': 0}

        client.get_picture_settings.side_effect = read_allowed_keys
        await controller.read()
        self.assertEqual(controller.level, 0)
        self.assertTrue(controller.verified)

    async def test_rejected_direct_write_uses_supported_fallback(self):
        controller, client = self.make_controller()
        client.set_system_settings.side_effect = RuntimeError('401 insufficient permissions')
        await controller.set_level(45)
        client.set_settings.assert_awaited_once_with('picture', {'backlight': 45})
        self.assertTrue(controller.verified)

    async def test_unchanged_value_is_not_reported_as_success(self):
        controller, client = self.make_controller()
        client.get_picture_settings.return_value = {'backlight': 80}
        with self.assertRaisesRegex(RuntimeError, 'kept its previous brightness'):
            await controller.set_level(45)
        self.assertEqual(controller.level, 80)

    async def test_failed_read_does_not_invent_a_value(self):
        controller, client = self.make_controller()
        client.get_picture_settings.side_effect = RuntimeError('not supported')
        await controller.set_level(45)
        self.assertIsNone(controller.level)
        self.assertFalse(controller.verified)
        self.assertIn('could not be confirmed', controller.error)

    async def test_disconnected_tv_provides_reconnect_message(self):
        controller, client = self.make_controller()
        client.is_connected = lambda: False
        with self.assertRaisesRegex(RuntimeError, 'reconnect'):
            await controller.set_level(45)
        client.set_system_settings.assert_not_awaited()

    def test_only_local_tv_addresses_are_accepted(self):
        self.assertEqual(private_ip('192.168.0.100'), '192.168.0.100')
        for value in ['127.0.0.1', '0.0.0.0', '8.8.8.8', '169.254.1.1', 'example.com', None]:
            with self.assertRaises(ValueError):
                private_ip(value)


if __name__ == '__main__':
    unittest.main()
