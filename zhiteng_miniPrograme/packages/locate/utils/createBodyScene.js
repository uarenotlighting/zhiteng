import * as THREE from '../libs/three-platformize/build/three.module.js'
import { WechatPlatform } from '../libs/three-platformize/src/WechatPlatform/index.js'
import { BytePlatform } from '../libs/three-platformize/src/BytePlatform/index.js'
import { GLTFLoader } from '../libs/three-platformize/examples/jsm/loaders/GLTFLoader.js'
import { OrbitControls } from '../libs/three-platformize/examples/jsm/controls/OrbitControls.js'
import { BODY_MODEL_URL } from './bodyModel.js'

const CLINICAL_COLOR = 0x9a9a9a

function createPlatform(canvas, width, height) {
  try {
    // eslint-disable-next-line no-undef
    if (typeof tt !== 'undefined' && typeof tt.getSystemInfoSync === 'function') {
      return new BytePlatform(canvas, width, height)
    }
  } catch (e) {
    /* ignore */
  }
  return new WechatPlatform(canvas, width, height)
}

function applyClinicalMaterial(root) {
  root.traverse((node) => {
    if (!node.isMesh || !node.material) return
    const materials = Array.isArray(node.material) ? node.material : [node.material]
    materials.forEach((mat) => {
      if (!mat) return
      if (mat.color) mat.color.setHex(CLINICAL_COLOR)
      mat.transparent = true
      mat.opacity = 0.72
      mat.roughness = 0.78
      mat.metalness = 0.02
      mat.side = THREE.DoubleSide
      mat.depthWrite = false
      mat.needsUpdate = true
    })
  })
}

function frameCamera(camera, controls, box, region) {
  const size = new THREE.Vector3()
  const center = new THREE.Vector3()
  box.getSize(size)
  box.getCenter(center)

  const height = Math.max(size.y, 0.001)
  let targetY = center.y
  let distance = height * 1.55

  if (region === 'head') {
    targetY = box.max.y - height * 0.12
    distance = height * 0.55
  } else if (region === 'lower') {
    targetY = box.min.y + height * 0.28
    distance = height * 0.7
  }

  const target = new THREE.Vector3(center.x, targetY, center.z)
  camera.position.set(target.x, target.y, target.z + distance)
  camera.near = distance / 100
  camera.far = distance * 100
  camera.updateProjectionMatrix()
  controls.target.copy(target)
  controls.update()
}

/** 把各端 readFile 结果稳妥转成当前 realm 的 ArrayBuffer */
function toArrayBuffer(data) {
  if (data == null) return null

  const tag = Object.prototype.toString.call(data)

  if (tag === '[object ArrayBuffer]' || data instanceof ArrayBuffer) {
    const src = new Uint8Array(data)
    const copy = new Uint8Array(src.byteLength)
    copy.set(src)
    return copy.buffer
  }

  if (
    ArrayBuffer.isView(data) ||
    tag === '[object Uint8Array]' ||
    tag === '[object Uint16Array]' ||
    tag === '[object DataView]'
  ) {
    const byteOffset = data.byteOffset || 0
    const byteLength = data.byteLength != null ? data.byteLength : data.length
    const src = new Uint8Array(data.buffer || data, byteOffset, byteLength)
    const copy = new Uint8Array(src.byteLength)
    copy.set(src)
    return copy.buffer
  }

  if (typeof data === 'string') {
    if (data.length >= 4 && data.charCodeAt(0) === 0x67 && data.charCodeAt(1) === 0x6c) {
      const copy = new Uint8Array(data.length)
      for (let i = 0; i < data.length; i += 1) copy[i] = data.charCodeAt(i) & 0xff
      return copy.buffer
    }
    if (typeof uni !== 'undefined' && typeof uni.base64ToArrayBuffer === 'function') {
      try {
        return uni.base64ToArrayBuffer(data)
      } catch (e) {
        return null
      }
    }
  }

  return null
}

function getFs() {
  if (typeof uni !== 'undefined' && uni.getFileSystemManager) return uni.getFileSystemManager()
  // eslint-disable-next-line no-undef
  if (typeof wx !== 'undefined' && wx.getFileSystemManager) return wx.getFileSystemManager()
  return null
}

function getUserDataPath() {
  try {
    // eslint-disable-next-line no-undef
    if (typeof wx !== 'undefined' && wx.env && wx.env.USER_DATA_PATH) return wx.env.USER_DATA_PATH
  } catch (e) {
    /* ignore */
  }
  try {
    // eslint-disable-next-line no-undef
    if (typeof tt !== 'undefined' && tt.env && tt.env.USER_DATA_PATH) return tt.env.USER_DATA_PATH
  } catch (e) {
    /* ignore */
  }
  return ''
}

function readBinaryFile(filePath) {
  return new Promise((resolve, reject) => {
    const fs = getFs()
    if (!fs) {
      reject(new Error('无文件系统 API'))
      return
    }

    const finish = (data) => {
      // 个别端会包一层
      if (data && data.data != null && !(data instanceof ArrayBuffer) && typeof data !== 'string' && !ArrayBuffer.isView(data)) {
        resolve(data.data)
        return
      }
      resolve(data)
    }

    // 先按二进制读
    fs.readFile({
      filePath,
      success: (res) => {
        const data = res && res.data
        if (data != null && (typeof data === 'string' ? data.length > 0 : true)) {
          // 若已是非空结果直接用；空字符串再试 base64
          if (typeof data === 'string' && data.length === 0) {
            readAsBase64()
            return
          }
          finish(data)
          return
        }
        readAsBase64()
      },
      fail: () => readAsBase64()
    })

    function readAsBase64() {
      fs.readFile({
        filePath,
        encoding: 'base64',
        success: (res) => {
          const b64 = res && res.data
          if (!b64) {
            reject(new Error(`base64 空 path=${filePath}`))
            return
          }
          if (typeof uni !== 'undefined' && typeof uni.base64ToArrayBuffer === 'function') {
            try {
              finish(uni.base64ToArrayBuffer(b64))
              return
            } catch (e) {
              /* fall through */
            }
          }
          // 手动 base64 → ArrayBuffer
          try {
            // eslint-disable-next-line no-undef
            const atobFn = typeof atob === 'function' ? atob : null
            if (!atobFn) {
              reject(new Error('无法解码 base64'))
              return
            }
            const bin = atobFn(b64)
            const out = new Uint8Array(bin.length)
            for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i)
            finish(out.buffer)
          } catch (e) {
            reject(e)
          }
        },
        fail: (err) => reject(err)
      })
    }
  })
}

function copyFile(srcPath, destPath) {
  return new Promise((resolve, reject) => {
    const fs = getFs()
    fs.copyFile({
      srcPath,
      destPath,
      success: resolve,
      fail: reject
    })
  })
}

export function createBodyScene(canvas, options = {}) {
  const width = options.width || canvas.width
  const height = options.height || canvas.height
  const platform = createPlatform(canvas, width, height)
  THREE.PLATFORM.set(platform)

  // 微信/抖音仅 webgl；直接短路 webgl2/2d，避免控制台刷 Invalid context type
  const rawGetContext = canvas.getContext.bind(canvas)
  canvas.getContext = (type, attrs) => {
    if (type === 'webgl2' || type === '2d') return null
    return rawGetContext('webgl', attrs || { antialias: true, alpha: true })
  }

  let gl = null
  try {
    gl = canvas.getContext('webgl', { antialias: true, alpha: true })
  } catch (e) {
    gl = null
  }

  const renderer = new THREE.WebGLRenderer({
    canvas,
    context: gl || undefined,
    antialias: true,
    alpha: true
  })
  renderer.setPixelRatio(Math.min(platform.window.devicePixelRatio || 2, 2))
  renderer.setSize(width, height, false)
  renderer.setClearColor(0xf7f7f7, 1)
  renderer.outputEncoding = THREE.sRGBEncoding

  const scene = new THREE.Scene()
  scene.background = new THREE.Color(0xf7f7f7)

  const camera = new THREE.PerspectiveCamera(35, width / height, 0.01, 100)
  camera.position.set(0, 1, 3)

  const ambient = new THREE.AmbientLight(0xffffff, 0.85)
  const key = new THREE.DirectionalLight(0xffffff, 0.75)
  key.position.set(2.2, 4.5, 3.2)
  const fill = new THREE.DirectionalLight(0xffffff, 0.35)
  fill.position.set(-2.5, 1.5, -1.5)
  scene.add(ambient, key, fill)

  const controls = new OrbitControls(camera, canvas)
  controls.enableDamping = true
  controls.dampingFactor = 0.08
  controls.enablePan = false
  controls.enableRotate = false
  controls.enableZoom = true
  controls.minDistance = 0.4
  controls.maxDistance = 8
  controls.target.set(0, 1, 0)

  const raycaster = new THREE.Raycaster()
  const pointer = new THREE.Vector2()
  const marker = new THREE.Mesh(
    new THREE.SphereGeometry(0.018, 16, 16),
    new THREE.MeshBasicMaterial({ color: 0xe64340 })
  )
  marker.visible = false
  scene.add(marker)

  let bodyRoot = null
  let bodyBox = new THREE.Box3()
  let disposed = false
  let raf = 0
  let region = options.region || 'full'

  const loader = new GLTFLoader()

  function renderLoop() {
    if (disposed) return
    raf = canvas.requestAnimationFrame(renderLoop)
    controls.update()
    renderer.render(scene, camera)
  }

  function applyGltf(gltf, resolve) {
    if (bodyRoot) scene.remove(bodyRoot)
    bodyRoot = gltf.scene
    applyClinicalMaterial(bodyRoot)
    scene.add(bodyRoot)
    bodyBox = new THREE.Box3().setFromObject(bodyRoot)
    frameCamera(camera, controls, bodyBox, region)
    resolve(bodyRoot)
  }

  function parseBuffer(data, path) {
    const ab = toArrayBuffer(data)
    if (!ab || ab.byteLength < 20) {
      const tag = Object.prototype.toString.call(data)
      throw new Error(
        `空数据 path=${path} type=${typeof data} tag=${tag} len=${data && (data.byteLength || data.length) || 0}`
      )
    }
    const u8 = new Uint8Array(ab, 0, 4)
    const head = String.fromCharCode(u8[0], u8[1], u8[2], u8[3])
    if (head !== 'glTF') {
      throw new Error(`头校验失败 path=${path} head=${head}`)
    }
    return ab
  }

  function loadModel(url = BODY_MODEL_URL) {
    return new Promise(async (resolve, reject) => {
      const candidates = [
        url,
        url.startsWith('/') ? url.slice(1) : `/${url}`,
        '/packages/locate/static/models/human_body.glb',
        'packages/locate/static/models/human_body.glb'
      ].filter((v, i, arr) => v && arr.indexOf(v) === i)

      let lastError = null

      for (const path of candidates) {
        try {
          const data = await readBinaryFile(path)
          const ab = parseBuffer(data, path)
          loader.parse(ab, '', (gltf) => applyGltf(gltf, resolve), (err) => reject(err))
          return
        } catch (err) {
          lastError = err
          console.warn('[PainBodyMap] load try fail', path, err && (err.errMsg || err.message || err))
        }
      }

      const userPath = getUserDataPath()
      if (userPath) {
        try {
          const src = '/packages/locate/static/models/human_body.glb'
          const dest = `${userPath}/zhiteng_human_body.glb`
          await copyFile(src, dest)
          const data = await readBinaryFile(dest)
          const ab = parseBuffer(data, dest)
          loader.parse(ab, '', (gltf) => applyGltf(gltf, resolve), (err) => reject(err))
          return
        } catch (err) {
          lastError = err
          console.warn('[PainBodyMap] copy/read fail', err && (err.errMsg || err.message || err))
        }
      }

      reject(lastError || new Error('模型文件读取为空'))
    })
  }

  function setRegion(nextRegion) {
    region = nextRegion || 'full'
    if (bodyRoot) frameCamera(camera, controls, bodyBox, region)
  }

  function setMarkerFromNdc(nx, ny) {
    if (!bodyRoot) return null
    pointer.set(nx * 2 - 1, -(ny * 2 - 1))
    raycaster.setFromCamera(pointer, camera)
    const hits = raycaster.intersectObject(bodyRoot, true)
    if (!hits.length) return null
    const hit = hits[0]
    marker.position.copy(hit.point)
    marker.visible = true
    const size = new THREE.Vector3()
    bodyBox.getSize(size)
    const center = new THREE.Vector3()
    bodyBox.getCenter(center)
    const x = size.x ? (hit.point.x - center.x) / size.x + 0.5 : 0.5
    const y = size.y ? 1 - (hit.point.y - bodyBox.min.y) / size.y : 0.5
    return {
      x: Math.min(0.98, Math.max(0.02, x)),
      y: Math.min(0.98, Math.max(0.02, y)),
      world: hit.point.clone(),
      name: guessPartName(x, y, region)
    }
  }

  function setMarkerNormalized(x, y) {
    if (!bodyRoot) return
    const size = new THREE.Vector3()
    bodyBox.getSize(size)
    const center = new THREE.Vector3()
    bodyBox.getCenter(center)
    marker.position.set(
      center.x + (x - 0.5) * size.x,
      bodyBox.min.y + (1 - y) * size.y,
      center.z + size.z * 0.15
    )
    marker.visible = true
  }

  function resize(nextWidth, nextHeight) {
    camera.aspect = nextWidth / nextHeight
    camera.updateProjectionMatrix()
    renderer.setSize(nextWidth, nextHeight, false)
  }

  function dispatchTouch(event) {
    if (platform && typeof platform.dispatchTouchEvent === 'function') {
      platform.dispatchTouchEvent(event)
    }
  }

  function dispose() {
    disposed = true
    if (raf) canvas.cancelAnimationFrame(raf)
    controls.dispose()
    renderer.dispose()
    THREE.PLATFORM.dispose()
  }

  renderLoop()

  return {
    loadModel,
    setRegion,
    setMarkerFromNdc,
    setMarkerNormalized,
    resize,
    dispose,
    dispatchTouch,
    controls
  }
}

function guessPartName(x, y, region) {
  if (region === 'head') {
    if (y < 0.45) return '头部'
    return '颈部'
  }
  if (region === 'lower') {
    if (y < 0.35) return '骨盆区域'
    if (y < 0.65) return '大腿'
    return '膝部'
  }
  if (y < 0.16) return '头部'
  if (y < 0.24) return '颈部'
  if (y < 0.38) return x < 0.35 || x > 0.65 ? '肩部' : '胸部'
  if (y < 0.5) return '腹部'
  if (y < 0.62) return '骨盆区域'
  if (y < 0.78) return '大腿'
  return '膝部'
}
