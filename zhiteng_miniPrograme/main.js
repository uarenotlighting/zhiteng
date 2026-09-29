import { createSSRApp } from 'vue'
import App from './App.vue'
import './uni_modules/tdesign-uniapp/components/theme.css'
import './styles/theme.css'

export function createApp() {
  const app = createSSRApp(App)
  return { app }
}
