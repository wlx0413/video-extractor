import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const distRoot = join(projectRoot, "dist");
const outputRoot = join(projectRoot, "dist-single");

let html = await readFile(join(distRoot, "index.html"), "utf8");

const stylesheetPattern = /<link[^>]+href="([^"]+\.css)"[^>]*>/g;
const stylesheets = [...html.matchAll(stylesheetPattern)];
for (const match of stylesheets) {
  const assetPath = join(distRoot, match[1].replace(/^\//, ""));
  const css = (await readFile(assetPath, "utf8")).replaceAll("</style", "<\\/style");
  html = html.replace(match[0], () => `<style>${css}</style>`);
}

const scriptPattern = /<script([^>]*)src="([^"]+\.js)"([^>]*)><\/script>/g;
const scripts = [...html.matchAll(scriptPattern)];
for (const match of scripts) {
  const assetPath = join(distRoot, match[2].replace(/^\//, ""));
  const javascript = (await readFile(assetPath, "utf8")).replaceAll("</script", "<\\/script");
  html = html.replace(
    match[0],
    () => `<script${match[1]}${match[3]}>${javascript}</script>`,
  );
}

if (stylesheets.length === 0 || scripts.length === 0) {
  throw new Error("没有找到可内联的 Vite CSS 或 JavaScript 资源。");
}

await mkdir(outputRoot, { recursive: true });
await Promise.all([
  writeFile(join(outputRoot, "index.html"), html),
  writeFile(join(outputRoot, "404.html"), html),
]);

console.log(`Single-file site written to ${outputRoot}`);
