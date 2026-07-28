import { rm, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { packager } from '@electron/packager';
import { makeUniversalApp } from '@electron/universal';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'out');
const universal = path.join(output, 'universal', 'PixelFerry Streamer.app');

await rm(output, { recursive: true, force: true });
await mkdir(path.dirname(universal), { recursive: true });

const common = {
  dir: root,
  out: output,
  name: 'PixelFerry Streamer',
  platform: 'darwin',
  appBundleId: 'cn.corneliamo.PixelFerry.Streamer',
  appCategoryType: 'public.app-category.utilities',
  appVersion: '0.1.0',
  buildVersion: '1',
  icon: process.env.PIXELFERRY_ICON || undefined,
  asar: true,
  overwrite: true,
  prune: true,
  extendInfo: {
    CFBundleDisplayName: 'PixelFerry Streamer',
    LSUIElement: true,
    NSLocalNetworkUsageDescription: 'PixelFerry shares a virtual display with browsers on your local network.',
    NSScreenCaptureUsageDescription: 'PixelFerry Streamer captures the PixelFerry virtual display for browser streaming.',
    NSHighResolutionCapable: true,
    NSPrincipalClass: 'AtomApplication',
  },
  ignore: [
    /^\/out($|\/)/,
    /^\/test($|\/)/,
    /^\/scripts($|\/)/,
  ],
};

const [armApp] = await packager({ ...common, arch: 'arm64' });
const [intelApp] = await packager({ ...common, arch: 'x64' });
await makeUniversalApp({
  arm64AppPath: armApp,
  x64AppPath: intelApp,
  outAppPath: universal,
  force: true,
});

console.log(universal);
