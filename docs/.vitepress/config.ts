import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Quo',
  description: 'Explicit, composable query builder for Crystal',

  // GitHub Pages base path
  base: '/Quo/',

  // Clean URLs without .html
  cleanUrls: true,

  // Last updated timestamp
  lastUpdated: true,

  head: [
    ['link', { rel: 'icon', href: '/Quo/favicon.ico' }],
    ['meta', { name: 'theme-color', content: '#7c3aed' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:title', content: 'Quo - Crystal Query Builder' }],
    ['meta', { property: 'og:description', content: 'Explicit, composable query builder and relations for Crystal' }],
  ],

  themeConfig: {
    logo: '/logo.svg',

    nav: [
      { text: 'Guide', link: '/guide/', activeMatch: '/guide/' },
      { text: 'API', link: '/api/', activeMatch: '/api/' },
      { text: 'Examples', link: '/examples/', activeMatch: '/examples/' },
      {
        text: 'v0.1.0',
        items: [
          { text: 'Changelog', link: '/changelog' },
          { text: 'Contributing', link: '/contributing' },
        ]
      }
    ],

    sidebar: {
      '/guide/': [
        {
          text: 'Introduction',
          items: [
            { text: 'What is Quo?', link: '/guide/' },
            { text: 'Getting Started', link: '/guide/getting-started' },
          ]
        },
        {
          text: 'Core Concepts',
          items: [
            { text: 'Queries', link: '/guide/queries' },
            { text: 'Expressions', link: '/guide/expressions' },
            { text: 'Relations', link: '/guide/relations' },
            { text: 'Scopes', link: '/guide/scopes' },
          ]
        },
        {
          text: 'Data Manipulation',
          items: [
            { text: 'Mutations', link: '/guide/mutations' },
            { text: 'Transactions', link: '/guide/transactions' },
          ]
        },
        {
          text: 'Advanced',
          items: [
            { text: 'Joins & Associations', link: '/guide/joins' },
            { text: 'Validation', link: '/guide/validation' },
            { text: 'Adapters', link: '/guide/adapters' },
            { text: 'Logging', link: '/guide/logging' },
          ]
        }
      ],
      '/api/': [
        {
          text: 'API Reference',
          items: [
            { text: 'Overview', link: '/api/' },
            { text: 'Query', link: '/api/query' },
            { text: 'InsertQuery', link: '/api/insert-query' },
            { text: 'UpdateQuery', link: '/api/update-query' },
            { text: 'DeleteQuery', link: '/api/delete-query' },
            { text: 'Relation', link: '/api/relation' },
            { text: 'Expression', link: '/api/expression' },
            { text: 'Schema', link: '/api/schema' },
            { text: 'Transaction', link: '/api/transaction' },
            { text: 'Logging', link: '/api/logging' },
            { text: 'Adapters', link: '/api/adapters' },
          ]
        }
      ],
      '/examples/': [
        {
          text: 'Examples',
          items: [
            { text: 'Overview', link: '/examples/' },
            { text: 'Basic Queries', link: '/examples/basic-queries' },
            { text: 'Complex Queries', link: '/examples/complex-queries' },
            { text: 'Real-World Patterns', link: '/examples/real-world' },
          ]
        }
      ]
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/alex-lairan/Quo' }
    ],

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright 2024-present Alexandre Lairan'
    },

    search: {
      provider: 'local'
    },

    editLink: {
      pattern: 'https://github.com/alex-lairan/Quo/edit/main/docs/:path',
      text: 'Edit this page on GitHub'
    },

    outline: {
      level: [2, 3]
    }
  },

  markdown: {
    theme: {
      light: 'github-light',
      dark: 'github-dark'
    },
    lineNumbers: true
  }
})
