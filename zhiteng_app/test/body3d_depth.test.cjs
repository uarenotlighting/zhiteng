// Run with: node --test test/body3d_depth.test.cjs
// Uses the shipped Three.js and GLB, with only the browser/rendering adapters
// stubbed. Raycasting, placement and bridge functions are the actual app code.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { before, test } = require('node:test');

const app = path.resolve(__dirname, '..');
global.window = {};
require(path.join(app, 'assets/web/libs/zhiteng-three-bundle.js'));
const { THREE, GLTFLoader } = window.ZhitengThree;
let skin;
let surfaceRegions;
let organs;

before(async () => {
  const bytes = fs.readFileSync(path.join(app, 'assets/models/skin.glb'));
  skin = (await new GLTFLoader().parseAsync(
    bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength), '',
  )).scene;
  const regionBytes = fs.readFileSync(path.join(app, 'assets/models/region.glb'));
  surfaceRegions = (await new GLTFLoader().parseAsync(
    regionBytes.buffer.slice(
      regionBytes.byteOffset,
      regionBytes.byteOffset + regionBytes.byteLength,
    ), '',
  )).scene;
  const organBytes = fs.readFileSync(path.join(app, 'assets/models/organ.glb'));
  organs = (await new GLTFLoader().parseAsync(
    organBytes.buffer.slice(
      organBytes.byteOffset,
      organBytes.byteOffset + organBytes.byteLength,
    ), '',
  )).scene;
});

function viewer(root, anatomicalRoot = null, regionRoot = null, organRoot = null) {
  const element = () => ({
    style: {}, clientWidth: 400, clientHeight: 600,
    querySelector: element, addEventListener() {},
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 400, height: 600 }),
  });
  class Renderer {
    setPixelRatio() {} setClearColor() {} setSize() {}
  }
  class Controls {
    constructor(camera) { this.camera = camera; this.target = new THREE.Vector3(); }
    addEventListener() {}
    update() { this.camera.lookAt(this.target); this.camera.updateMatrixWorld(true); }
  }
  const messages = [];
  const context = vm.createContext({
    window: {
      ZhitengThree: {
        THREE: { ...THREE, WebGLRenderer: Renderer }, OrbitControls: Controls,
        GLTFLoader, DRACOLoader: class { setDecoderPath() {} },
      },
      ZhitengChannel: { postMessage: (s) => messages.push(JSON.parse(s)) },
      addEventListener() {},
    },
    document: { getElementById: element },
    location: { search: '' }, URLSearchParams, performance,
    requestAnimationFrame() {}, console,
  });
  const html = fs.readFileSync(path.join(app, 'assets/web/body3d.html'), 'utf8');
  const source = html.split('<script>').at(-1).split('</script>')[0];
  vm.runInContext(source, context);
  context.testSkin = root || skin.clone(true);
  context.testAnatomy = anatomicalRoot;
  context.testRegions = regionRoot;
  context.testOrgans = organRoot;
  vm.runInContext(`
    styleLayer(testSkin, 'skin');
    roots.set('skin', testSkin);
    scene.add(testSkin);
    if (testAnatomy) {
      styleLayer(testAnatomy, 'muscle');
      roots.set('muscle', testAnatomy);
      scene.add(testAnatomy);
    }
    if (testRegions) {
      surfaceRegionRoot = testRegions;
      surfaceRegionRoot.updateMatrixWorld(true);
    }
    if (testOrgans) {
      styleLayer(testOrgans, 'organ');
      roots.set('organ', testOrgans);
      scene.add(testOrgans);
    }
    scene.updateMatrixWorld(true);
    globalThis.api = {
      select(origin, target) {
        camera.position.fromArray(origin);
        controls.target.fromArray(target);
        controls.update();
        ensureMarker();
        marker.visible = true;
        const direction = new THREE.Vector3().fromArray(target).sub(camera.position).normalize();
        return placeOnRay(camera.position.clone(), direction, 0);
      },
      move: nudge,
      shape: setMarkerShape,
      tap: pick,
      blocked(x, y) { return pointerHitsStageControl(x, y); },
      shield(rects) { window.ZhitengBridge.setPlacementShields(rects); },
      report: reportMarker,
      clear: window.ZhitengBridge.clearMarker,
      sideView() {
        const shown = showDepthView();
        if (shown) { stepViewAnimation(performance.now() + 1000); controls.update(); }
        return shown;
      },
      state() {
        const lineMesh = surfaceMark && surfaceMark.children.find(
          (child) => child.geometry && child.geometry.parameters && child.geometry.parameters.path,
        );
        return {
          position: marker.position.toArray(), depth: markerDepth,
          available: markerAvailableDepth, scale: markerScale,
          anchor: lineAnchor && lineAnchor.toArray(),
          inward: markerInward && markerInward.toArray(),
          camera: camera.position.toArray(),
          locatorOpacity: markerLocator.material.opacity,
          haloOpacity: markerHalo && markerHalo.material.opacity,
          guideVisible: depthGuide.visible,
          guide: Array.from(depthGuide.geometry.attributes.position.array),
          entry: depthEntryRing.position.toArray(),
          buttonVisible: depthViewButton.style.display === 'block',
          lineRadius: lineMesh && lineMesh.geometry.parameters.radius,
          lineOffset: lineMesh && lineMesh.position.clone().add(surfaceMark.position),
          curve: lineMesh && lineMesh.geometry.parameters.path,
        };
      },
      turn(origin) { camera.position.fromArray(origin); controls.update(); },
      project() { return marker.position.clone().project(camera).toArray(); },
      projectEntry() { return lineAnchor.clone().project(camera).toArray(); },
      setLineAngle(angle) { setLineAngle(angle); },
      organ(group, isolate = false) {
        activeOrganGroup = group;
        isolateOrganGroup = isolate;
        applyOrganAppearance(false);
        const result = {};
        roots.get('organ').traverse((node) => {
          if (!node.isMesh) return;
          result[node.userData.organId] = {
            group: node.userData.organGroupId,
            visible: node.visible,
            opacity: node.material.opacity,
          };
        });
        return result;
      },
      frame(value, view = 'front') {
        frameRegion(value);
        setView(view);
        stepViewAnimation(performance.now() + 1000);
        controls.update();
        return camera.clone();
      },
    };
  `, context);
  return { ...context.api, messages };
}

test('curated organ GLB is complete, grouped, and contains no reproductive anatomy', () => {
  const meshes = [];
  organs.traverse((node) => { if (node.isMesh) meshes.push(node); });
  assert.equal(meshes.length, 17);
  const ids = new Set(meshes.map((node) => node.userData.organId));
  for (const required of [
    'heart', 'left_lung', 'right_lung', 'liver', 'gallbladder', 'stomach',
    'pancreas', 'spleen', 'small_intestine', 'large_intestine',
    'left_kidney', 'right_kidney', 'left_ureter', 'right_ureter',
    'urinary_bladder', 'esophagus', 'trachea',
  ]) assert.ok(ids.has(required), required);
  const serialized = JSON.stringify(meshes.map((node) => node.userData)).toLowerCase();
  for (const excluded of [
    'uterus', 'ovary', 'vagina', 'prostate', 'testis', 'penis', 'genital',
  ]) assert.equal(serialized.includes(excluded), false, excluded);
});

test('organ focus dims other groups and isolate hides them', () => {
  const v = viewer(null, null, null, organs.clone(true));
  const focused = v.organ('urinary');
  assert.equal(focused.left_kidney.visible, true);
  assert.equal(focused.left_kidney.opacity, 1);
  assert.equal(focused.heart.visible, true);
  assert.equal(focused.heart.opacity, 0.09);

  const isolated = v.organ('urinary', true);
  assert.equal(isolated.left_kidney.visible, true);
  assert.equal(isolated.heart.visible, false);
});

test('taps on overlaid controls do not move the pain point', () => {
  const v = viewer();
  assert.equal(v.blocked(200, 20), true);
  assert.equal(v.blocked(200, 590), true);
  assert.equal(v.blocked(200, 300), false);
  v.shield([{ x: 340, y: 180, w: 48, h: 150 }]);
  assert.equal(v.blocked(360, 240), true);
  assert.equal(v.blocked(200, 240), false);

  assert.equal(v.select([0, 1.4, 3], [0, 1.4, 0]), true);
  const before = v.state().position.slice();
  v.tap(200, 590);
  v.tap(360, 240);
  assert.deepEqual(v.state().position, before);
});

test('actual body permits repeated depth steps through the hollow skin', () => {
  const v = viewer();
  for (const [label, x, y, minimumDepth] of [
    ['head', 0, 1.8, 0.08], ['chest', 0, 1.4, 0.08],
    ['abdomen', 0, 1.1, 0.08], ['pelvis', 0, 0.95, 0.08],
    ['thigh', 0.12, 0.7, 0.08], ['calf', 0.13, 0.4, 0.06],
    ['forearm', 0.25, 1.1, 0.03],
  ]) {
    assert.equal(v.select([x, y, 3], [x, y, 0]), true, label);
    const start = v.state();
    assert.ok(start.available > minimumDepth, `${label}: depth range ${start.available}`);
    for (let step = 1; step <= minimumDepth / 0.01; step++) {
      assert.equal(v.move(0, 0, 0.01), true, label);
      assert.ok(Math.abs(v.state().depth - step * 0.01) < 1e-6, `${label}: step ${step}`);
    }
    assert.ok(start.position[2] - v.state().position[2] >= minimumDepth - 1e-6, label);
    v.move(0, 0, -1);
    assert.ok(v.state().depth < 1e-6, `${label}: returns to surface`);
  }
});

test('line, dot and bridge XYZ move together while the reticle stays on the ray', () => {
  const v = viewer();
  v.select([0, 1.4, 3], [0, 1.4, 0]);
  v.shape('line');
  const start = v.state();
  const projected = v.project();
  for (let i = 0; i < 5; i++) v.move(0, 0, 0.01);
  const state = v.state();
  assert.ok(Math.abs(state.depth - 0.05) < 1e-6);
  assert.ok(state.curve.points.some((p) => p.clone().add(state.lineOffset)
    .distanceTo(new THREE.Vector3(...state.position)) < 1e-7));
  assert.ok(Math.abs(state.curve.points[0].z + state.lineOffset.z
    - start.curve.points[0].z + 0.05) < 1e-6);
  assert.equal(state.curve, start.curve, 'holding depth reuses the surface geometry');
  assert.ok(Math.abs(v.project()[0] - projected[0]) < 1e-6);
  assert.ok(Math.abs(v.project()[1] - projected[1]) < 1e-6);
  assert.equal(v.messages.at(-1).payload.depth, 0.05);
  assert.equal(v.messages.at(-1).payload.localZ, Number(state.position[2].toFixed(4)));
});

function curveExtent(points) {
  const min = points[0].clone();
  const max = points[0].clone();
  for (const point of points) {
    min.min(point);
    max.max(point);
  }
  return max.sub(min);
}

test('rotating a line re-drapes it on the skin instead of spinning a straight bar', () => {
  const v = viewer();
  assert.equal(v.select([0, 1.25, 3], [0, 1.25, 0]), true);
  v.shape('line');
  const vertical = v.state();
  const verticalSpan = curveExtent(vertical.curve.points);
  assert.ok(verticalSpan.y > verticalSpan.x * 1.4, `along the body: ${verticalSpan.toArray()}`);

  v.setLineAngle(Math.PI / 2);
  const turned = v.state();
  const turnedSpan = curveExtent(turned.curve.points);
  assert.ok(turnedSpan.x > turnedSpan.y * 1.2, `across the body: ${turnedSpan.toArray()}`);
  assert.deepEqual(turned.position, vertical.position);

  const centreZ = turned.position[2];
  for (const point of turned.curve.points) {
    const z = point.z + turned.lineOffset.z;
    assert.ok(z > centreZ - 0.03, `left the surface: ${z}`);
  }
  const endZ = Math.min(
    turned.curve.points[0].z,
    turned.curve.points.at(-1).z,
  ) + turned.lineOffset.z;
  assert.ok(centreZ - endZ > 0.004, `ends should follow the chest curve, drop ${centreZ - endZ}`);
});

test('actual body depth works from front, back and both sides', () => {
  const v = viewer();
  for (const y of [1.8, 1.4, 1.1]) {
    for (const [x, z] of [[0, 3], [0, -3], [3, 0], [-3, 0]]) {
      assert.equal(v.select([x, y, z], [0, y, 0]), true, `${x}, ${y}, ${z}`);
      const before = v.state();
      const steps = Math.min(5, Math.floor(before.available / 0.01));
      assert.ok(steps >= 2, `${x}, ${y}, ${z}: body range ${before.available}`);
      for (let i = 1; i <= steps; i++) {
        v.move(0, 0, 0.01);
        assert.ok(Math.abs(v.state().depth - i * 0.01) < 1e-6);
      }
    }
  }
});

function hollowBox(width, height, depth, z = 0) {
  const group = new THREE.Group();
  const outer = new THREE.BoxGeometry(width, height, depth);
  const inner = new THREE.BoxGeometry(width - 0.002, height - 0.002, depth - 0.002);
  const indices = inner.index.array;
  for (let i = 0; i < indices.length; i += 3) {
    [indices[i + 1], indices[i + 2]] = [indices[i + 2], indices[i + 1]];
  }
  for (const geometry of [outer, inner]) {
    group.add(new THREE.Mesh(geometry, new THREE.MeshBasicMaterial()));
  }
  group.position.z = z;
  return group;
}

test('depth stops at the selected part before a gap and can always return', () => {
  const root = new THREE.Group();
  root.add(hollowBox(0.12, 0.4, 0.06));
  root.add(hollowBox(0.3, 0.5, 0.2, -0.4));
  const v = viewer(root);
  v.select([0, 0, 3], [0, 0, 0]);
  assert.ok(Math.abs(v.state().available - 0.06) < 1e-6);
  for (let i = 0; i < 20; i++) v.move(0, 0, 0.01);
  assert.ok(Math.abs(v.state().depth - 0.06) < 1e-6);
  v.move(0, 0, -0.01);
  assert.ok(Math.abs(v.state().depth - 0.05) < 1e-6);
});

test('genuinely thin body parts retain their actual depth limit', () => {
  const v = viewer(hollowBox(0.02, 0.08, 0.012));
  v.select([0, 0, 3], [0, 0, 0]);
  v.move(0, 0, 0.01);
  assert.ok(Math.abs(v.state().depth - 0.01) < 1e-6);
  v.move(0, 0, 0.01);
  assert.ok(Math.abs(v.state().depth - 0.012) < 1e-6);
});

test('surface picks report the named open-source structure underneath', () => {
  const anatomy = new THREE.Group();
  const pectoral = new THREE.Mesh(
    new THREE.BoxGeometry(0.2, 0.4, 0.08),
    new THREE.MeshBasicMaterial(),
  );
  pectoral.userData.bodyPartId = 'pectoralis_major_left';
  pectoral.userData.zt_source_name = 'Clavicular head of pectoralis major muscle.l';
  anatomy.add(pectoral);
  const v = viewer(hollowBox(0.3, 0.5, 0.2), anatomy);
  assert.equal(v.select([0, 0, 3], [0, 0, 0]), true);
  v.report('tap');
  assert.equal(v.messages.at(-1).payload.anatomicalStructureId, 'pectoralis_major_left');
  assert.equal(
    v.messages.at(-1).payload.anatomicalSourceName,
    'Clavicular head of pectoralis major muscle.l',
  );
});

test('actual surface proxy reports the exact source region independently of the skin mesh', () => {
  const v = viewer(null, null, surfaceRegions.clone(true));
  assert.equal(v.select([0, 1.4, 3], [0, 1.4, 0]), true);
  v.report('tap');
  const payload = v.messages.at(-1).payload;
  assert.equal(payload.surfaceRegionId, 'epigastric_region_left');
  assert.equal(payload.surfaceRegionSourceName, 'Epigastric region.l');
  assert.equal(payload.bodyPartId, payload.surfaceRegionId);
  assert.notEqual(payload.meshId, payload.surfaceRegionId);
});

test('published surface proxy retains all region IDs and source names', () => {
  const regions = [];
  surfaceRegions.traverse((object) => {
    if (object.isMesh && object.userData.bodyPartId) {
      regions.push([object.userData.bodyPartId, object.userData.zt_source_name]);
    }
  });
  assert.equal(regions.length, 230);
  assert.equal(new Set(regions.map(([id]) => id)).size, 230);
  assert.ok(regions.every(([, sourceName]) => typeof sourceName === 'string' && sourceName.length));
});

test('orbiting to the back does not reverse depth or snap to a foreground part', () => {
  const root = new THREE.Group();
  root.add(hollowBox(0.12, 0.4, 0.06));
  root.add(hollowBox(0.3, 0.5, 0.2, -0.4));
  const v = viewer(root);
  v.select([0, 0, 3], [0, 0, 0]);
  v.move(0, 0, 0.03);
  v.turn([0, 0, -3]);
  v.move(0, 0, 0.01);
  assert.ok(Math.abs(v.state().position[2] + 0.01) < 1e-6);
  assert.ok(Math.abs(v.state().depth - 0.04) < 1e-6);
});

test('actual body keeps moving on screen after rotating to observe depth', () => {
  const v = viewer();
  v.select([0, 1.4, 3], [0, 1.4, 0]);
  v.shape('line');
  v.move(0, 0, 0.08);
  const initial = v.state();
  v.turn([3, 1.4, 0]);
  let screen = v.project();
  for (let i = 1; i <= 10; i++) {
    v.move(0, 0, 0.01);
    const state = v.state();
    const nextScreen = v.project();
    assert.ok(Math.abs(state.depth - (0.08 + 0.01 * i)) < 1e-6);
    assert.ok(Math.abs(state.position[2] - initial.position[2] + 0.01 * i) < 1e-6);
    assert.ok(Math.abs(nextScreen[0] - screen[0]) > 0.005, 'sideways screen displacement each step');
    assert.deepEqual(state.anchor, initial.anchor);
    assert.deepEqual(state.inward, initial.inward);
    assert.equal(state.curve, initial.curve);
    assert.ok(state.curve.points.some((p) => p.clone().add(state.lineOffset)
      .distanceTo(new THREE.Vector3(...state.position)) < 1e-7));
    screen = nextScreen;
  }
});

test('depth remains observable through 24 cm, with the guide anchored to the skin', () => {
  const v = viewer(hollowBox(0.4, 0.6, 0.4));
  v.select([0, 0, 3], [0, 0, 0]);
  v.move(0, 0, 0.06);
  const before = v.state();
  assert.equal(v.sideView(), true);
  const side = v.state();
  assert.deepEqual(side.position, before.position, 'view changes must not move pain coordinate');
  assert.deepEqual(side.anchor, before.anchor);
  assert.deepEqual(side.inward, before.inward);
  assert.equal(side.available, before.available);
  let previous = side;
  let screen = v.project();
  for (let i = 7; i <= 24; i++) {
    v.move(0, 0, 0.01);
    const state = v.state();
    assert.ok(Math.abs(state.depth - i * 0.01) < 1e-6);
    assert.ok(state.locatorOpacity < previous.locatorOpacity, 'no 6 cm visual saturation');
    assert.ok(state.haloOpacity < previous.haloOpacity);
    assert.ok(state.locatorOpacity >= 0.42, 'internal point remains legible');
    assert.deepEqual(state.camera, side.camera, 'depth input does not follow with the camera');
    assert.equal(state.guideVisible, true);
    assert.deepEqual(state.entry, before.anchor);
    assert.ok(new THREE.Vector3(...state.guide.slice(0, 3))
      .distanceTo(new THREE.Vector3(...before.anchor)) < 1e-7);
    assert.ok(new THREE.Vector3(...state.guide.slice(3))
      .distanceTo(new THREE.Vector3(...state.position)) < 1e-7);
    const nextScreen = v.project();
    assert.ok(Math.abs(nextScreen[0] - screen[0]) > 0.002);
    assert.equal(v.messages.at(-1).payload.depth, i / 100);
    previous = state;
    screen = nextScreen;
  }
  for (const shape of ['line', 'area', 'radiate', 'point']) {
    v.shape(shape);
    assert.deepEqual(v.state().position, previous.position);
    assert.deepEqual(v.state().entry, previous.anchor);
    assert.equal(v.state().guideVisible, true);
  }
  v.move(0, 0, -1);
  assert.equal(v.state().depth, 0);
  assert.equal(v.state().guideVisible, false);
  v.move(0, 0, 0.02);
  v.clear();
  assert.equal(v.state().guideVisible, false);
  assert.equal(v.state().buttonVisible, false);
  assert.equal(v.sideView(), false);
});

test('side-depth inspection is stable for front, side and vertical placement rays', () => {
  for (const origin of [[0, 0, 3], [3, 0, 0], [0, 3, 0]]) {
    const v = viewer(hollowBox(0.4, 0.6, 0.4));
    assert.equal(v.select(origin, [0, 0, 0]), true);
    v.move(0, 0, 0.08);
    assert.equal(v.sideView(), true);
    const before = v.project();
    v.move(0, 0, 0.01);
    const after = v.project();
    assert.ok(after.every(Number.isFinite));
    assert.ok(Math.hypot(after[0] - before[0], after[1] - before[1]) > 0.002);
  }
});

test('side-depth inspection fits the surface entry and a 24 cm deep point at close zoom', () => {
  const v = viewer(hollowBox(0.4, 0.6, 0.4));
  v.select([0, 0, 0.6], [0, 0, 0]);
  v.move(0, 0, 0.24);
  const before = v.state();
  v.sideView();
  for (const endpoint of [v.projectEntry(), v.project()]) {
    assert.ok(Math.abs(endpoint[0]) < 0.8 && Math.abs(endpoint[1]) < 0.8,
      `both ends should be in the stage: ${endpoint}`);
  }
  assert.deepEqual(v.state().position, before.position);
  assert.deepEqual(v.state().anchor, before.anchor);
});

test('after drawing a line a second tap can still reach the body', () => {
  const v = viewer();
  v.select([0, 1.4, 3], [0, 1.4, 0]);
  v.shape('line');
  v.move(0, 0, 0.03);
  v.tap(200, 300);
  assert.equal(v.state().depth, 0);
  assert.equal(v.messages.at(-1).payload.source, 'tap');
});

test('new 3D indicator is minimum sized and line diameter defaults to 3 mm', () => {
  const v = viewer();
  v.select([0, 1.4, 3], [0, 1.4, 0]);
  v.shape('line');
  assert.equal(v.state().scale, 0.5);
  assert.equal(v.state().lineRadius * 2, 0.003);
});

test('actual regional frames include shoulders, hands and feet from all four views', () => {
  skin.updateMatrixWorld(true);
  const bounds = new THREE.Box3().setFromObject(skin);
  const height = bounds.max.y - bounds.min.y;
  const points = [];
  skin.traverse((node) => {
    if (!node.isMesh) return;
    const positions = node.geometry.attributes.position;
    for (let i = 0; i < positions.count; i++) {
      points.push(new THREE.Vector3().fromBufferAttribute(positions, i).applyMatrix4(node.matrixWorld));
    }
  });
  const v = viewer();
  for (const [region, minimum, maximum] of [
    ['head', 0.78, 1], ['upper', 0.40, 0.84], ['lower', 0.02, 0.54],
  ]) {
    const regionalPoints = points.filter((point) => {
      const y = (point.y - bounds.min.y) / height;
      return y >= minimum && y <= maximum;
    });
    for (const view of ['front', 'back', 'left', 'right']) {
      const camera = v.frame(region, view);
      // The record stage is wider than this test canvas. Judge horizontal
      // fit the way the phone shows it.
      camera.aspect = 0.82;
      camera.updateProjectionMatrix();
      for (const point of regionalPoints) {
        const projected = point.clone().project(camera);
        const y = (1 - projected.y) / 2 * 600;
        assert.ok(Math.abs(projected.x) < 1 && y >= 56 && y <= 600 - 36,
          `${region}/${view}: clipped body vertex ${point.toArray()} at ${projected.toArray()}`);
      }
    }
  }
});

test('region framing preserves existing pain coordinates and anatomical naming coordinates', () => {
  const v = viewer();
  v.select([0, 1.4, 3], [0, 1.4, 0]);
  v.shape('line');
  v.move(0, 0, 0.06);
  const before = v.state();
  const named = v.messages.at(-1).payload;
  for (const region of ['head', 'upper', 'lower', 'full']) {
    v.frame(region);
    v.report('layers', false);
    const current = v.state();
    assert.deepEqual(current.position, before.position);
    assert.deepEqual(current.anchor, before.anchor);
    assert.equal(current.depth, before.depth);
    assert.equal(current.curve, before.curve);
    const payload = v.messages.at(-1).payload;
    assert.equal(payload.bodyHeightFraction, named.bodyHeightFraction);
    assert.equal(payload.bodyLateralFraction, named.bodyLateralFraction);
  }
});
