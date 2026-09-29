<script>
import { bootstrapApp } from './stores/app'

export default {
  onLaunch() {
    bootstrapApp()
  },
  onShow() {
    bootstrapApp()
  }
}
</script>

<style>
page {
  min-height: 100%;
  background: var(--color-bg-page);
  color: var(--color-text-primary);
  font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif;
}
</style>
