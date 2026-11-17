# About this site

This site uses [VitePress](https://vitepress.dev/). User guides live in `docs-site/guide/`, and the build guide comes from `docs/DEVELOPMENT.md`. The shorter user guide in `docs/USER_GUIDE.md` is maintained separately.

## Preview locally

From the `docs-site` directory, run:

```sh
npm ci
npm run dev
```

Open the local address printed in the terminal. Run `npm run build` to check the production build. The Vite override in `package.json` keeps VitePress on a patched Vite 6 release; check compatibility and the dependency audit when updating it.

## Publish to GitHub Pages

The configured base path is `/Roblox-Account-Manager-Mac/`, for a project site at `intraducine.github.io/Roblox-Account-Manager-Mac/`. A custom domain or a different repository name requires a base path change.

In the repository's Pages settings, select **GitHub Actions** as the source. The documentation workflow builds and publishes the site when documentation changes reach `main`. You can also run it from the Actions tab. See the [VitePress GitHub Pages guide](https://vitepress.dev/guide/deploy#github-pages) for more details.
