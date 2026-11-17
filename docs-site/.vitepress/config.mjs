import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Roblox Account Manager',
  description: 'Documentation for Roblox Account Manager for Mac.',
  base: '/Roblox-Account-Manager-Mac/',
  cleanUrls: true,
  themeConfig: {
    siteTitle: 'Account Manager for Mac',
    nav: [
      { text: 'User guide', link: '/guide/get-started' },
      { text: 'Development', link: '/developer/architecture' },
      { text: 'Download', link: 'https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/latest' }
    ],
    sidebar: [
      { text: 'Using the app', items: [
        { text: 'Get started', link: '/guide/get-started' },
        { text: 'Accounts and groups', link: '/guide/accounts' },
        { text: 'Games and servers', link: '/guide/games-and-servers' },
        { text: 'Launch settings and windows', link: '/guide/launch-settings' },
        { text: 'Backup and privacy', link: '/guide/backup' },
        { text: 'Troubleshooting', link: '/guide/troubleshooting' }
      ] },
      { text: 'Developing the app', items: [
        { text: 'Architecture', link: '/developer/architecture' },
        { text: 'Build, test, and release', link: '/development' },
        { text: 'About this site', link: '/site' }
      ] }
    ],
    search: {
      provider: 'local',
      options: {
        miniSearch: {
          options: {
            processTerm: (term) => {
              const word = term.toLowerCase()
              return ['a', 'an', 'the', 'i', 'my', 'how', 'do', 'can', 'to', 'is', 'what', 'where'].includes(word) ? null : word
            }
          },
          searchOptions: { combineWith: 'AND' }
        }
      }
    },
    socialLinks: [{ icon: 'github', link: 'https://github.com/intraducine/Roblox-Account-Manager-Mac' }]
  }
})
