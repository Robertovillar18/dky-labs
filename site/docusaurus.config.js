// @ts-check
// `@type` JSDoc annotations allow editor autocompletion and type checking
// (when paired with `@ts-check`).
// There are various equivalent ways to declare your Docusaurus config.
// See: https://docusaurus.io/docs/api/docusaurus-config

import {themes as prismThemes} from 'prism-react-renderer';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'DKY Labs',
  tagline: 'DKY Labs | AI & Data',
  favicon: 'img/logo_small.png',

  url: 'http://localhost:3000',   // en dev
  baseUrl: '/',

  onBrokenLinks: 'throw',
  markdown: { hooks: { onBrokenMarkdownLinks: 'warn' } },

  i18n: { defaultLocale: 'es', locales: ['es','en'] },

  presets: [
    [
      'classic',
      ({
        docs: {
          sidebarPath: './sidebars.js'
        },
        blog: false,
        theme: { customCss: './src/css/custom.css' },
      }),
    ],
  ],
  themeConfig: {
    // image: 'img/docusaurus-social-card.jpg',
    colorMode: { respectPrefersColorScheme: true },
    navbar: {
      title: 'DKY Labs',
      logo: {
        src: 'img/logo_small.png',
      },
      items: [
        { to: '/servicios', label: 'Servicios', position: 'left' },
        { to: '/sobre-nosotros', label: 'Sobre nosotros', position: 'left' },
        { to: '/contacto', label: 'Contacto', position: 'left' },
        {href: 'https://www.linkedin.com/in/roberto-villar-5b1a4b3b', label: 'LinkedIn', position: 'right' },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        { title: 'Legal', items: [
          {label: 'Términos', to: '/terminos'},
          {label: 'Privacidad', to: '/privacidad'},
        ]},
      ],
      copyright: `© ${new Date().getFullYear()} DKY Labs.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  },
};

export default config;
