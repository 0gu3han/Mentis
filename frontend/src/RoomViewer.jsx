// src/RoomViewer.jsx
import React, { useEffect, useRef, useState } from 'react'
import * as THREE from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { USDZLoader } from 'three/examples/jsm/loaders/USDZLoader.js'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { CSS2DRenderer, CSS2DObject } from 'three/examples/jsm/renderers/CSS2DRenderer.js'
import { VRButton } from 'three/examples/jsm/webxr/VRButton.js'
import { XRControllerModelFactory } from 'three/examples/jsm/webxr/XRControllerModelFactory.js'
import { listAnchors, createAnchor, createObject, deleteAnchor } from './api'
import NoteEditor from './NoteEditor'

export default function RoomViewer({ roomId, glbUrl }) {
  const mountRef = useRef()

  // ── Refs that the Three.js loop / event handlers read live ────────────────
  const sceneRef        = useRef(null)
  const anchorGroupRef  = useRef(null)     // THREE.Group holding the pin spheres
  const anchorMeshesRef = useRef(new Map()) // anchorId → { inner, outer }
  const placingRef      = useRef(false)    // mirrors placingAnchor state
  const labelRef        = useRef('Note')   // mirrors label state
  const markerRadiusRef = useRef(0.05)     // set after model loads
  const sidebarRef        = useRef(null)
  const setSelectedRef    = useRef(null)     // stable setter ref for use inside effect closures
  const labelRendererRef  = useRef(null)
  const labelObjectsRef   = useRef([])       // CSS2DObjects in scene, cleaned up on anchor change

  const viewerRef = useRef(null)
  const [isFullscreen,     setIsFullscreen]     = useState(false)
  const [label,            setLabel]            = useState('Note')
  const [anchors,          setAnchors]          = useState([])
  const [placingAnchor,    setPlacingAnchor]    = useState(false)
  const [selectedAnchorId, setSelectedAnchorId] = useState(null)
  const [noteEditor, setNoteEditor] = useState(null) // { anchorId, label, title, body, saving }
  const [modelState, setModelState] = useState('loading') // 'loading' | 'loaded' | 'error' | 'converting'
  const [modelError, setModelError] = useState('')

  // Keep refs in sync — no re-render needed
  useEffect(() => { placingRef.current   = placingAnchor    }, [placingAnchor])
  useEffect(() => { labelRef.current     = label            }, [label])
  setSelectedRef.current = setSelectedAnchorId

  // ── Fullscreen ───────────────────────────────────────────────────────────
  useEffect(() => {
    function onFsChange() {
      setIsFullscreen(!!document.fullscreenElement)
    }
    document.addEventListener('fullscreenchange', onFsChange)
    return () => document.removeEventListener('fullscreenchange', onFsChange)
  }, [])

  function toggleFullscreen() {
    if (!document.fullscreenElement) {
      viewerRef.current?.requestFullscreen()
    } else {
      document.exitFullscreen()
    }
  }

  // Reset model state whenever the URL changes
  useEffect(() => { setModelState('loading'); setModelError('') }, [glbUrl])

  // ── Main scene setup — runs ONCE per glbUrl, never on placingAnchor ───────
  useEffect(() => {
    if (!mountRef.current) return
    const container = mountRef.current
    let disposed = false

    // Scene
    const scene = new THREE.Scene()
    scene.background = new THREE.Color(0x111111)
    sceneRef.current = scene

    // Anchor pin group (kept separate so raycasting skips it)
    const anchorGroup = new THREE.Group()
    anchorGroup.name = 'anchor-pins'
    scene.add(anchorGroup)
    anchorGroupRef.current = anchorGroup

    // Camera
    const w = container.clientWidth  || 800
    const h = container.clientHeight || 600
    const camera = new THREE.PerspectiveCamera(60, w / h, 0.01, 1000)
    camera.position.set(2, 1.6, 2)

    // Renderer
    const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' })
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.setSize(w, h, false)
    renderer.outputColorSpace  = THREE.SRGBColorSpace
    renderer.toneMapping       = THREE.ACESFilmicToneMapping
    renderer.xr.enabled        = true
    renderer.domElement.style.display = 'block'
    container.appendChild(renderer.domElement)

    // VR entry button — auto-hides if WebXR is unavailable
    const vrButton = VRButton.createButton(renderer)
    vrButton.style.position  = 'absolute'
    vrButton.style.bottom    = '16px'
    vrButton.style.left      = '50%'
    vrButton.style.transform = 'translateX(-50%)'
    vrButton.style.zIndex    = '10'
    container.appendChild(vrButton)

    // CSS2D overlay for floating anchor labels
    const labelRenderer = new CSS2DRenderer()
    labelRenderer.setSize(w, h)
    labelRenderer.domElement.style.position = 'absolute'
    labelRenderer.domElement.style.top = '0'
    labelRenderer.domElement.style.left = '0'
    labelRenderer.domElement.style.pointerEvents = 'none'
    container.style.position = 'relative'
    container.appendChild(labelRenderer.domElement)
    labelRendererRef.current = labelRenderer

    // Controls
    const controls = new OrbitControls(camera, renderer.domElement)
    controls.enableDamping  = true
    controls.dampingFactor  = 0.05
    controls.minDistance    = 0.5
    controls.maxDistance    = 100

    // Lights
    scene.add(new THREE.AmbientLight(0xffffff, 0.6))
    const dir = new THREE.DirectionalLight(0xffffff, 0.8)
    dir.position.set(5, 10, 5)
    scene.add(dir)
    scene.add(new THREE.HemisphereLight(0xffffff, 0x444444, 0.5))
    scene.add(new THREE.GridHelper(10, 10))

    // Detect format then load with the right loader
    let roomMesh = null

    function onModelLoaded(object, axisFixed = false) {
      if (disposed) return
      roomMesh = object

      // Correct the Y-axis flip that Blender introduces when converting iOS USDZ.
      // The server sets X-Axis-Fixed when the GLB went through the Blender pipeline.
      if (axisFixed) roomMesh.rotation.x = Math.PI

      roomMesh.traverse((o) => {
        if (o.isMesh) {
          o.material.side = THREE.DoubleSide
          if (o.material.map) o.material.map.anisotropy = 16
        }
      })
      scene.add(roomMesh)

      const box = new THREE.Box3().setFromObject(roomMesh)
      if (!box.isEmpty()) {
        const center = box.getCenter(new THREE.Vector3())
        const size   = box.getSize(new THREE.Vector3())
        const maxDim = Math.max(size.x, size.y, size.z)
        // Center horizontally but keep vertical position so the floor stays grounded
        roomMesh.position.set(-center.x, -center.y, -center.z)

        markerRadiusRef.current = Math.min(Math.max(maxDim * 0.005, 0.015), 0.08)

        // Position camera outside the room looking in at a comfortable angle
        const fov  = camera.fov * (Math.PI / 180)
        const dist = (maxDim / (2 * Math.tan(fov / 2))) * 1.8
        camera.position.set(dist * 0.6, dist * 0.4, dist * 0.8)
        camera.near = maxDim * 0.001
        camera.far  = maxDim * 20
        camera.updateProjectionMatrix()
        camera.lookAt(0, 0, 0)
        controls.target.set(0, 0, 0)
        controls.minDistance = maxDim * 0.05
        controls.maxDistance = maxDim * 8
        controls.update()
      }
      setModelState('loaded')
    }

    function onModelError(err) {
      console.error('Model load error:', err)
      if (!disposed) {
        setModelState('error')
        setModelError(err?.message || String(err))
      }
    }

    fetch(glbUrl, { method: 'HEAD' })
      .then((r) => {
        if (disposed) return
        const ct        = r.headers.get('Content-Type') || ''
        const axisFixed = r.headers.get('X-Axis-Fixed') === 'true'
        if (ct.includes('usdz') || ct.includes('usd')) {
          // Server is still converting — retry in 15 s
          setModelState('converting')
          setTimeout(() => {
            if (!disposed) { setModelState('loading'); setModelError('') }
          }, 15000)
          return
        }
        new GLTFLoader().load(
          glbUrl,
          (gltf) => onModelLoaded(gltf.scene, axisFixed),
          undefined,
          onModelError
        )
      })
      .catch(() => {
        if (!disposed) {
          new GLTFLoader().load(
            glbUrl,
            (gltf) => onModelLoaded(gltf.scene, false),
            undefined,
            onModelError
          )
        }
      })

    // Raycasting — listeners are ALWAYS attached; the ref gates behaviour
    const raycaster = new THREE.Raycaster()
    const mouse     = new THREE.Vector2()

    // ── VR Controllers ────────────────────────────────────────────────────────
    const controllerModelFactory = new XRControllerModelFactory()
    const xrControllers = []
    for (let i = 0; i < 2; i++) {
      const controller = renderer.xr.getController(i)

      // Pointer ray line
      const lineGeo = new THREE.BufferGeometry().setFromPoints([
        new THREE.Vector3(0, 0, 0),
        new THREE.Vector3(0, 0, -1),
      ])
      const ray = new THREE.Line(lineGeo, new THREE.LineBasicMaterial({ color: 0xa8b4ff }))
      ray.scale.z = 10
      controller.add(ray)

      // Trigger-press → place anchor
      controller.addEventListener('select', () => {
        if (!placingRef.current || !roomMesh) return
        const tempMatrix = new THREE.Matrix4().identity().extractRotation(controller.matrixWorld)
        const origin = new THREE.Vector3().setFromMatrixPosition(controller.matrixWorld)
        const dir    = new THREE.Vector3(0, 0, -1).applyMatrix4(tempMatrix).normalize()
        raycaster.set(origin, dir)
        const hits = raycaster.intersectObjects([roomMesh], true)
        if (!hits.length || !hits[0].face) return
        const { point, face, object } = hits[0]
        const normal = face.normal.clone()
          .applyMatrix3(new THREE.Matrix3().getNormalMatrix(object.matrixWorld))
          .normalize()
        createAnchor({
          room_id: roomId,
          label:   labelRef.current,
          pos:     [point.x, point.y, point.z],
          normal:  [normal.x, normal.y, normal.z],
        })
          .then((res) => { if (res.anchor_id) refreshAnchors() })
          .catch(console.error)
        setPlacingAnchor(false)
      })

      scene.add(controller)

      // Controller grip model
      const grip = renderer.xr.getControllerGrip(i)
      grip.add(controllerModelFactory.createControllerModel(grip))
      scene.add(grip)

      xrControllers.push({ controller, grip })
    }

    function onPointerMove(e) {
      if (!placingRef.current) return
      const rect  = renderer.domElement.getBoundingClientRect()
      mouse.x     =  ((e.clientX - rect.left) / rect.width)  * 2 - 1
      mouse.y     = -((e.clientY - rect.top)  / rect.height) * 2 + 1
      raycaster.setFromCamera(mouse, camera)
      const hits  = roomMesh ? raycaster.intersectObjects([roomMesh], true) : []
      renderer.domElement.style.cursor = hits.length ? 'crosshair' : 'not-allowed'
    }

    function onPointerDown(e) {
      if (e.button !== 0) return
      const rect = renderer.domElement.getBoundingClientRect()
      mouse.x    =  ((e.clientX - rect.left) / rect.width)  * 2 - 1
      mouse.y    = -((e.clientY - rect.top)  / rect.height) * 2 + 1
      raycaster.setFromCamera(mouse, camera)

      if (!placingRef.current) {
        // ── Select mode: check if a pin was clicked ────────────────────────
        const group = anchorGroupRef.current
        if (group && group.children.length) {
          const pinHits = raycaster.intersectObjects(group.children, false)
          if (pinHits.length) {
            const id = pinHits[0].object.userData.anchorId
            if (id != null) {
              setSelectedRef.current(id)
              renderer.domElement.style.cursor = 'default'
              return
            }
          }
        }
        return  // not placing — ignore clicks on empty space
      }

      // ── Place mode: raycast against the room mesh ──────────────────────────
      if (!roomMesh) return
      const hits = raycaster.intersectObjects([roomMesh], true)
      if (!hits.length || !hits[0].face) return

      const { point, face, object } = hits[0]
      const normal = face.normal.clone()
        .applyMatrix3(new THREE.Matrix3().getNormalMatrix(object.matrixWorld))
        .normalize()

      createAnchor({
        room_id: roomId,
        label:   labelRef.current,
        pos:     [point.x,  point.y,  point.z],
        normal:  [normal.x, normal.y, normal.z],
      })
        .then((res) => { if (res.anchor_id) refreshAnchors() })
        .catch(console.error)

      setPlacingAnchor(false)
      renderer.domElement.style.cursor = 'default'
    }

    renderer.domElement.addEventListener('pointermove', onPointerMove)
    renderer.domElement.addEventListener('pointerdown', onPointerDown)

    // Resize
    function handleResize() {
      if (disposed || !container) return
      const rw = container.clientWidth
      const rh = container.clientHeight
      if (!rw || !rh) return
      camera.aspect = rw / rh
      camera.updateProjectionMatrix()
      renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
      renderer.setSize(rw, rh, false)
      labelRenderer.setSize(rw, rh)
    }
    window.addEventListener('resize', handleResize)
    document.addEventListener('fullscreenchange', handleResize)

    // Loop — setAnimationLoop is required for WebXR frames
    renderer.setAnimationLoop(() => {
      if (disposed) return
      controls.update()
      renderer.render(scene, camera)
      labelRenderer.render(scene, camera)
    })

    return () => {
      disposed = true
      renderer.setAnimationLoop(null)
      window.removeEventListener('resize', handleResize)
      document.removeEventListener('fullscreenchange', handleResize)
      renderer.domElement.removeEventListener('pointermove', onPointerMove)
      renderer.domElement.removeEventListener('pointerdown', onPointerDown)
      xrControllers.forEach(({ controller, grip }) => {
        scene.remove(controller)
        scene.remove(grip)
      })
      controls.dispose()
      renderer.dispose()
      if (container.contains(renderer.domElement)) container.removeChild(renderer.domElement)
      if (container.contains(labelRenderer.domElement)) container.removeChild(labelRenderer.domElement)
      if (container.contains(vrButton)) container.removeChild(vrButton)
      labelRendererRef.current = null
      labelObjectsRef.current  = []
      sceneRef.current       = null
      anchorGroupRef.current = null
    }
  }, [glbUrl]) // ← placingAnchor intentionally NOT here

  // ── Sync anchor pin spheres into the scene whenever anchors change ─────────
  useEffect(() => {
    const group = anchorGroupRef.current
    if (!group) return

    // Remove old pins
    while (group.children.length) {
      const c = group.children[0]
      c.geometry?.dispose()
      c.material?.dispose()
      group.remove(c)
    }

    const r = markerRadiusRef.current || 0.03
    const meshMap = new Map()

    // Clean up old CSS2D labels
    labelObjectsRef.current.forEach((obj) => {
      sceneRef.current?.remove(obj)
      obj.element?.remove()
    })
    const newLabelObjects = []

    anchors.forEach((a, idx) => {
      const pos = new THREE.Vector3(...a.pos)

      // Inner solid pin — store anchorId for raycasting
      const inner = new THREE.Mesh(
        new THREE.SphereGeometry(r, 16, 16),
        new THREE.MeshBasicMaterial({ color: 0xdc2626 })
      )
      inner.position.copy(pos)
      inner.userData.anchorId = a.id
      group.add(inner)

      // Outer glow halo — also store id so either sphere is clickable
      const outer = new THREE.Mesh(
        new THREE.SphereGeometry(r * 1.5, 16, 16),
        new THREE.MeshBasicMaterial({ color: 0xdc2626, transparent: true, opacity: 0.15, side: THREE.BackSide })
      )
      outer.position.copy(pos)
      outer.userData.anchorId = a.id
      group.add(outer)

      meshMap.set(a.id, { inner, outer })

      // Floating label bubble (CSS2DObject)
      const div = document.createElement('div')
      div.className = 'anchor-label'
      div.innerHTML = `<span class="anchor-label-num">${idx + 1}</span><span class="anchor-label-text">${a.label || `Anchor ${a.id}`}</span>`
      div.dataset.anchorId = String(a.id)
      div.style.pointerEvents = 'auto'
      div.addEventListener('click', () => setSelectedRef.current?.(a.id))
      const labelObj = new CSS2DObject(div)
      labelObj.position.copy(pos)
      labelObj.position.y += r * 2.5
      sceneRef.current?.add(labelObj)
      newLabelObjects.push(labelObj)
    })

    anchorMeshesRef.current = meshMap
    labelObjectsRef.current = newLabelObjects
  }, [anchors])

  // ── Highlight selected anchor in scene + scroll sidebar ─────────────────
  useEffect(() => {
    anchorMeshesRef.current.forEach(({ inner, outer }, id) => {
      const selected = id === selectedAnchorId
      inner.material.color.set(selected ? 0xfbbf24 : 0xdc2626)  // yellow when selected
      outer.material.color.set(selected ? 0xfbbf24 : 0xdc2626)
      outer.material.opacity = selected ? 0.35 : 0.15
      inner.scale.setScalar(selected ? 1.4 : 1.0)
    })

    // Highlight matching CSS2D label
    labelObjectsRef.current.forEach((obj) => {
      const id = Number(obj.element.dataset.anchorId)
      obj.element.classList.toggle('selected', id === selectedAnchorId)
    })

    if (selectedAnchorId != null && sidebarRef.current) {
      const el = sidebarRef.current.querySelector(`[data-anchor-id="${selectedAnchorId}"]`)
      el?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
    }
  }, [selectedAnchorId, anchors])

  // ── Data helpers ──────────────────────────────────────────────────────────
  async function refreshAnchors() {
    try {
      const data = await listAnchors(roomId)
      setAnchors(data.anchors || [])
    } catch (e) { console.error('refreshAnchors:', e) }
  }

  useEffect(() => { refreshAnchors() }, [roomId])

  function openNoteEditor(anchor) {
    setNoteEditor({ anchorId: anchor.id, label: anchor.label || `Anchor ${anchor.id}`, title: '', body: '', saving: false })
  }

  async function saveNote() {
    if (!noteEditor || !noteEditor.title.trim()) return
    setNoteEditor((n) => ({ ...n, saving: true }))
    try {
      const res = await createObject({ anchor_id: noteEditor.anchorId, title: noteEditor.title, body: noteEditor.body, kind: 'text' })
      if (res.object_id) {
        await refreshAnchors()
        setNoteEditor(null)
      }
    } catch (err) {
      setNoteEditor((n) => ({ ...n, saving: false }))
      console.error('saveNote:', err)
    }
  }

  async function removeAnchor(e, anchor) {
    e.stopPropagation()  // don't trigger the li onClick (select)
    if (!window.confirm(`Delete anchor "${anchor.label || `Anchor ${anchor.id}`}" and all its notes?`)) return
    try {
      await deleteAnchor(anchor.id)
      if (selectedAnchorId === anchor.id) setSelectedAnchorId(null)
      if (noteEditor?.anchorId === anchor.id) setNoteEditor(null)
      await refreshAnchors()
    } catch (err) { console.error('removeAnchor:', err) }
  }

  // ── JSX ───────────────────────────────────────────────────────────────────
  return (
    <div className="room-viewer" ref={viewerRef}>
      <div className="toolbar">
        <input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Anchor label" />
        <button
          className={`place-anchor-btn${placingAnchor ? ' active' : ''}`}
          onClick={() => setPlacingAnchor((p) => !p)}
        >
          {placingAnchor ? '✓ Click on surface to place anchor' : '📌 Place Anchor'}
        </button>
        <span className="toolbar-status">
          {placingAnchor
            ? 'Click on any surface in the model'
            : 'Toggle "Place Anchor" then click the model'}
        </span>
        <button className="fullscreen-btn" onClick={toggleFullscreen} title={isFullscreen ? 'Exit fullscreen' : 'Enter fullscreen'}>
          {isFullscreen ? '⊠' : '⛶'} {isFullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
        </button>
      </div>

      <div className="stage" ref={mountRef}>
        {modelState === 'loading' && (
          <div className="model-overlay">
            <div className="model-overlay-spinner" />
            <p>Loading 3D model…</p>
          </div>
        )}
        {modelState === 'converting' && (
          <div className="model-overlay">
            <div className="model-overlay-spinner" />
            <p>Converting model to web format…</p>
            <p className="model-overlay-hint">Blender is processing your scan server-side. Checking again in 15 s.</p>
          </div>
        )}
        {modelState === 'error' && (
          <div className="model-overlay model-overlay--error">
            <p>Could not display this model.</p>
            <p className="model-overlay-hint">
              The model file may be in an unsupported or corrupted format. Download it to open locally.
            </p>
            <a className="model-overlay-download" href={glbUrl} download>
              Download model file
            </a>
          </div>
        )}
      </div>

      <div className="sidebar" ref={sidebarRef}>
        <h4>Anchors ({anchors.length})</h4>

        {/* ── Note editor panel ── */}
        {noteEditor && (
          <NoteEditor
            anchorLabel={noteEditor.label}
            title={noteEditor.title}
            body={noteEditor.body}
            saving={noteEditor.saving}
            onTitleChange={(v) => setNoteEditor((n) => ({ ...n, title: v }))}
            onBodyChange={(v)  => setNoteEditor((n) => ({ ...n, body:  v }))}
            onSave={saveNote}
            onCancel={() => setNoteEditor(null)}
          />
        )}

        <ul>
          {anchors.length === 0 && (
            <li style={{ color: '#555', fontSize: 13, border: 'none', background: 'none' }}>
              No anchors yet. Click "Place Anchor" then click the model.
            </li>
          )}
          {anchors.map((a) => (
            <li
              key={a.id}
              data-anchor-id={a.id}
              className={`anchor-item${selectedAnchorId === a.id ? ' selected' : ''}`}
              onClick={() => setSelectedAnchorId(a.id)}
            >
              <div className="anchor-header">
                <strong>{a.label || `Anchor ${a.id}`}</strong>
                <button className="delete-btn" title="Delete anchor" onClick={(e) => removeAnchor(e, a)}>×</button>
              </div>
              {a.objects && a.objects.length > 0 && (
                <div className="anchor-objects">
                  {a.objects.map((obj) => (
                    <div key={obj.id} className="object-item">
                      <strong>{obj.title}</strong>
                      {obj.body && <div className="object-body">{obj.body}</div>}
                    </div>
                  ))}
                </div>
              )}
              <button onClick={() => openNoteEditor(a)}>Attach note</button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
