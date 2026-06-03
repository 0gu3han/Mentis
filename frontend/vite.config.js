import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: true, // listen on 0.0.0.0 so network devices can reach Vite
    proxy: {
      '/rooms': 'http://localhost:5001',
      '/auth':  'http://localhost:5001',
      '/anchors': 'http://localhost:5001',
      '/objects': 'http://localhost:5001',
      '/uploads': 'http://localhost:5001',
    },
  },
})