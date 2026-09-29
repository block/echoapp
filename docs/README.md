# EchoApp documentation site

This directory is the source for the public EchoApp documentation site at
<https://block.github.io/echoapp/>. It uses GitHub Pages' built-in Jekyll support and has no
JavaScript package or build dependency.

## Preview locally

Install Ruby and Bundler, then run:

```sh
cd docs
bundle install
bundle exec jekyll serve --baseurl /echoapp
```

Open <http://127.0.0.1:4000/echoapp/>.

## Publish

In the public `block/echoapp` repository settings, configure GitHub Pages to deploy from the
`main` branch and the `/docs` folder. Changes merged under this directory are then published by
GitHub Pages automatically.

Keep the site public by design: do not include internal repository links, private tooling,
company-only setup steps, customer data, or screenshots captured from non-public apps.
