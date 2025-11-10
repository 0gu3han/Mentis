// src/RoomViewer.jsx
import React, { useEffect, useRef, useState } from 'react'
import * as THREE from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { listAnchors, createAnchor, createObject } from './api'

export default function RoomViewer({ roomId, glbUrl }) {
  const mountRef = useRef()
  const [label, setLabel] = useState('Note')
  const [anchors, setAnchors] = useState([])

  useEffect(() => {
    let renderer, scene, camera, controls, raycaster, mouse
    let disposed = false

    // setup scene
    scene = new THREE.Scene()
    scene.background = new THREE.Color(0xf3f3f3)

    // Get container dimensions accurately
    const container = mountRef.current
    const containerWidth = container.clientWidth || container.offsetWidth
    const containerHeight = container.clientHeight || container.offsetHeight
    
    // Ensure we have valid dimensions
    if (containerWidth === 0 || containerHeight === 0) {
      console.warn('Container has zero dimensions, using defaults')
    }
    
    const aspect = containerWidth / containerHeight || 1
    camera = new THREE.PerspectiveCamera(60, aspect, 0.01, 1000)
    camera.position.set(2, 1.6, 2)

    renderer = new THREE.WebGLRenderer({ 
      antialias: true,
      alpha: false,
      powerPreference: 'high-performance',
      precision: 'highp'
    })
    
    // Set pixel ratio first
    const pixelRatio = Math.min(window.devicePixelRatio, 2)
    renderer.setPixelRatio(pixelRatio)
    
    // Set renderer size - this is the actual render resolution
    renderer.setSize(containerWidth, containerHeight, false)
    
    renderer.shadowMap.enabled = false
    renderer.outputColorSpace = THREE.SRGBColorSpace
    renderer.toneMapping = THREE.ACESFilmicToneMapping
    renderer.toneMappingExposure = 1.0
    
    // Canvas will be sized by CSS to fill container
    // renderer.setSize() sets the internal resolution
    renderer.domElement.style.display = 'block'
    container.appendChild(renderer.domElement)

    controls = new OrbitControls(camera, renderer.domElement)
    controls.enableDamping = true
    controls.dampingFactor = 0.05
    controls.minDistance = 0.5
    controls.maxDistance = 100
    controls.enableZoom = true
    controls.enablePan = true
    controls.enableRotate = true

    // Better lighting setup
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.6)
    scene.add(ambientLight)
    
    const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8)
    directionalLight.position.set(5, 10, 5)
    scene.add(directionalLight)
    
    const hemisphereLight = new THREE.HemisphereLight(0xffffff, 0x444444, 0.5)
    scene.add(hemisphereLight)

    const grid = new THREE.GridHelper(10, 10)
    scene.add(grid)

    // load room model
    const loader = new GLTFLoader()
    loader.load(
      glbUrl,
      (gltf) => {
        const room = gltf.scene
        room.traverse((o) => {
          if (o.isMesh) {
            o.material.side = THREE.DoubleSide
            // Improve material quality
            if (o.material.map) {
              o.material.map.anisotropy = 16
            }
          }
        })
        scene.add(room)
        
        // Fit model to view properly
        const box = new THREE.Box3().setFromObject(room)
        if (!box.isEmpty()) {
          const center = box.getCenter(new THREE.Vector3())
          const size = box.getSize(new THREE.Vector3())
          const maxDim = Math.max(size.x, size.y, size.z)
          
          // Center the model
          room.position.sub(center)
          
          // Adjust camera to view the model - better calculation
          const fov = camera.fov * (Math.PI / 180)
          const cameraZ = maxDim / (2 * Math.tan(fov / 2))
          const distance = cameraZ * 1.5
          
          camera.position.set(
            distance * 0.7,
            distance * 0.6,
            distance * 0.7
          )
          camera.lookAt(0, 0, 0)
          controls.target.set(0, 0, 0)
          controls.update()
          
          // Update controls min/max based on model size
          controls.minDistance = maxDim * 0.3
          controls.maxDistance = maxDim * 5
        }
      },
      undefined,
      (error) => {
        console.error('Error loading GLB:', error)
      }
    )

    // raycasting setup
    raycaster = new THREE.Raycaster()
    mouse = new THREE.Vector2()

    function onPointerDown(e) {
      const rect = renderer.domElement.getBoundingClientRect()
      mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1
      mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1
      raycaster.setFromCamera(mouse, camera)
      const hits = raycaster.intersectObjects(scene.children, true)
      if (!hits.length) return
      const { point, face, object } = hits[0]
      const normal = face?.normal.clone()
        .applyMatrix3(new THREE.Matrix3().getNormalMatrix(object.matrixWorld))
        .normalize()
      dropAnchor(point, normal)
    }

    renderer.domElement.addEventListener('pointerdown', onPointerDown)

    // Handle window resize
    function handleResize() {
      if (disposed || !mountRef.current) return
      const container = mountRef.current
      const width = container.clientWidth || container.offsetWidth
      const height = container.clientHeight || container.offsetHeight
      
      if (width === 0 || height === 0) return
      
      const aspect = width / height || 1
      camera.aspect = aspect
      camera.updateProjectionMatrix()
      
      const pixelRatio = Math.min(window.devicePixelRatio, 2)
      renderer.setPixelRatio(pixelRatio)
      renderer.setSize(width, height, false)
    }
    window.addEventListener('resize', handleResize)

    function tick() {
      if (disposed) return
      controls.update()
      renderer.render(scene, camera)
      requestAnimationFrame(tick)
    }
    tick()

    return () => {
      disposed = true
      window.removeEventListener('resize', handleResize)
      renderer.domElement.removeEventListener('pointerdown', onPointerDown)
      renderer.dispose()
      if (mountRef.current && mountRef.current.contains(renderer.domElement)) {
        mountRef.current.removeChild(renderer.domElement)
      }
    }
  }, [glbUrl])

  async function refreshAnchors() {
    const data = await listAnchors(roomId)
    setAnchors(data.anchors || [])
  }

  useEffect(() => { refreshAnchors() }, [roomId])

  async function dropAnchor(point, normal) {
    const res = await createAnchor({
      room_id: roomId,
      label,
      pos: [point.x, point.y, point.z],
      normal: [normal.x, normal.y, normal.z]
    })
    if (res.anchor_id) refreshAnchors()
  }

  async function addTextObject(anchorId) {
    const title = prompt('Title for this memory object?', 'Quick fact')
    const body = prompt('Body text?', 'Short mnemonic or summary...')
    if (!title) return
  
    // 1) create on backend
    const res = await createObject({ anchor_id: anchorId, title, body, kind: 'text' })
  
    // 2) optimistically show in UI (persisted for this session)
    setObjectsByAnchor(prev => {
      const arr = prev[anchorId] ? [...prev[anchorId]] : []
      arr.push({ id: res?.object_id, title, body })
      return { ...prev, [anchorId]: arr }
    })
  
    alert('Saved! It will appear in your review queue.')
  }
  

  return (
    <div className="room-viewer">
      <div className="toolbar">
        <input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Anchor label" />
        <span>Click any surface to add an anchor.</span>
      </div>
      <div className="stage" ref={mountRef} />
      <div className="sidebar">
        <h4>Anchors ({anchors.length})</h4>
        <ul>
          {anchors.map((a) => (
            <li key={a.id}>
              <strong>{a.label || 'Anchor ' + a.id}</strong>
              <div>pos: {a.pos.map((n) => n.toFixed(2)).join(', ')}</div>
              <button onClick={() => addTextObject(a.id)}>Attach text</button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
