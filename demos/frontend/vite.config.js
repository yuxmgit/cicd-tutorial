import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 开发用 proxy 解决跨域；生产由 Nginx 同源反代，不需要 CORS 配置。
export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    host: '0.0.0.0',
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8000',
        changeOrigin: true
      }
    }
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
    chunkSizeWarningLimit: 600
  },
  test: {
    environment: 'jsdom',
    globals: true,
    coverage: {
      provider: 'v8',
      reporter: ['text'],
      // 起步阈值 50；第 07 章会带你把阈值提到 80，并解释为什么不能一步到位
      thresholds: { lines: 50, functions: 50 }
    }
  }
})
