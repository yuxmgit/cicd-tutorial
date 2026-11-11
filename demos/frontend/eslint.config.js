import js from '@eslint/js'
import pluginVue from 'eslint-plugin-vue'
import globals from 'globals'

export default [
  js.configs.recommended,
  ...pluginVue.configs['flat/recommended'],
  {
    languageOptions: {
      globals: {
        ...globals.browser,
        ...globals.node
      }
    },
    rules: {
      'vue/multi-word-component-names': 'off',
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }]
    }
  },
  {
    ignores: ['dist/**', 'node_modules/**', 'coverage/**']
  }
]
