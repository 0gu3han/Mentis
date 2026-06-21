import React, { useEffect, useRef, useState } from 'react'
import { login, createRoom, listRooms, roomGlbUrl, deleteRoom } from './api'
import RoomViewer from './RoomViewer'
import SketchfabViewer from './SketchfabViewer'
import HeroBg from './HeroBg'

const DEMO_ROOMS = [
  {
    id: 'sketchfab-927ef282eceb47e29397b52147d4d6c3',
    name: 'Living Room',
    category: 'Home',
    sketchfabId: '927ef282eceb47e29397b52147d4d6c3',
    author: 'fleewortep',
  },
  {
    id: 'sketchfab-44e7a9cfed67431e827d0cbaabd462c7',
    name: 'Loft Apartment',
    category: 'Home',
    sketchfabId: '44e7a9cfed67431e827d0cbaabd462c7',
    author: 'Zeps3D',
  },
  {
    id: 'sketchfab-3ecfa670dbd946ec80b49d7df74ab453',
    name: 'Modular Classroom Preview',
    category: 'Education',
    sketchfabId: '3ecfa670dbd946ec80b49d7df74ab453',
    author: 'lazarys',
  },
  {
    id: 'sketchfab-79615d823a9149069dcd06c20bc9707f',
    name: 'The Billiards Room',
    category: 'Other',
    sketchfabId: '79615d823a9149069dcd06c20bc9707f',
    author: 'The Hallwyl Museum',
  },
]

const CATEGORY_ORDER = ['Home', 'Education', 'Office', 'Other']

function groupByCategory(rooms) {
  const map = {}
  for (const room of rooms) {
    const cat = room.category || 'Other'
    if (!map[cat]) map[cat] = []
    map[cat].push(room)
  }
  return CATEGORY_ORDER.filter((c) => map[c]).map((c) => ({ category: c, rooms: map[c] }))
}

// Persist login across page refreshes
function getSavedUser() {
  try { return JSON.parse(sessionStorage.getItem('mentis_user')) } catch { return null }
}
function saveUser(u) {
  sessionStorage.setItem('mentis_user', JSON.stringify(u))
}
function clearUser() {
  sessionStorage.removeItem('mentis_user')
}

function formatSize(bytes) {
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export default function App() {
  const [user, setUser]         = useState(getSavedUser)
  const [emailInput, setEmail]  = useState('')
  const [loginError, setLoginError] = useState(null)
  const [loggingIn, setLoggingIn]   = useState(false)
  const [rooms, setRooms]       = useState([])
  const [activeRoom, setActiveRoom] = useState(null)
  const [uploading, setUploading]   = useState(false)
  const [roomName, setRoomName]     = useState('')
  const [selectedFile, setSelectedFile] = useState(null)
  const [dragOver, setDragOver]     = useState(false)
  const fileRef = useRef()

  function selectRoom(room) {
    setActiveRoom(room)
    setTimeout(() => {
      document.getElementById('viewer-section')?.scrollIntoView({ behavior: 'smooth' })
    }, 80)
  }

  // Load personal rooms whenever user changes
  useEffect(() => {
    if (user) listRooms(user.user_id).then((r) => setRooms(r.rooms ?? []))
  }, [user])

  async function doLogin(email) {
    setLoggingIn(true)
    setLoginError(null)
    try {
      const u = await login(email)
      saveUser(u)
      setUser(u)
    } catch (err) {
      setLoginError(err.message || String(err))
    } finally {
      setLoggingIn(false)
    }
  }

  function handleLoginSubmit(e) {
    e.preventDefault()
    if (emailInput.trim()) doLogin(emailInput.trim())
  }

  function handleLogout() {
    clearUser()
    setUser(null)
    setRooms([])
  }

  async function onDeleteRoom(room) {
    if (!window.confirm(`Delete "${room.name}"? This cannot be undone.`)) return
    try {
      await deleteRoom(room.id)
      if (activeRoom?.id === room.id) setActiveRoom(null)
      const roomsData = await listRooms(user.user_id)
      setRooms(roomsData.rooms ?? [])
    } catch (err) {
      alert(`Delete failed: ${err.message}`)
    }
  }

  function handleDragOver(e) {
    e.preventDefault()
    setDragOver(true)
  }

  function handleDragLeave(e) {
    if (!e.currentTarget.contains(e.relatedTarget)) setDragOver(false)
  }

  function handleDrop(e) {
    e.preventDefault()
    setDragOver(false)
    const file = e.dataTransfer.files[0]
    if (file) setSelectedFile(file)
  }

  function handleFileChange(e) {
    setSelectedFile(e.target.files[0] ?? null)
  }

  function clearFile(e) {
    e.stopPropagation()
    setSelectedFile(null)
    fileRef.current.value = ''
  }

  async function onUpload() {
    if (!user) { alert('Please sign in first'); return }
    if (!selectedFile) { alert('Pick a GLB / USDZ file'); return }
    setUploading(true)
    try {
      const result = await createRoom(user.user_id, roomName.trim() || 'My Room', selectedFile)
      if (result.error) { alert(`Upload failed: ${result.error}`); return }
      setRoomName('')
      setSelectedFile(null)
      fileRef.current.value = ''
      const roomsData = await listRooms(user.user_id)
      setRooms(roomsData.rooms ?? [])
    } catch (error) {
      alert(`Upload failed: ${error.message}`)
    } finally {
      setUploading(false)
    }
  }

  return (
    <div className="app">
      <header className="hero-header">
        <HeroBg />
        <div className="hero-content">
          <h1>Mentis</h1>
          <p className="hero-subtitle">Your 3D Memory Palace</p>

          {/* Auth bar */}
          {user ? (
            <div className="auth-bar">
              <span className="auth-email">{user.email}</span>
              <button className="auth-signout" onClick={handleLogout}>Sign out</button>
            </div>
          ) : (
            <form className="login-form" onSubmit={handleLoginSubmit}>
              <input
                className="login-input"
                type="email"
                placeholder="your@email.com"
                value={emailInput}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
              <button className="login-btn" type="submit" disabled={loggingIn}>
                {loggingIn ? 'Signing in…' : 'Sign in'}
              </button>
              <button
                className="login-btn demo"
                type="button"
                disabled={loggingIn}
                onClick={() => doLogin('demo@mentis.app')}
              >
                Try demo
              </button>
              {loginError && <p className="login-error">{loginError}</p>}
            </form>
          )}
        </div>
      </header>

      {/* ── Upload (signed-in users only) ── */}
      {user && (
        <section className="upload-section">
          <div className="upload-card">
            <div className="upload-card-header">
              <span className="upload-card-title">Upload Room</span>
              <div className="upload-format-badges">
                {['GLB', 'GLTF', 'USDZ', 'OBJ'].map((f) => (
                  <span key={f} className="format-badge">{f}</span>
                ))}
              </div>
            </div>

            <div className="upload-body">
              <input
                className="upload-name-input"
                placeholder="Room name"
                value={roomName}
                onChange={(e) => setRoomName(e.target.value)}
              />

              <div
                className={`upload-dropzone${dragOver ? ' dragover' : ''}${selectedFile ? ' has-file' : ''}`}
                onDragOver={handleDragOver}
                onDragLeave={handleDragLeave}
                onDrop={handleDrop}
                onClick={() => fileRef.current.click()}
              >
                <input
                  ref={fileRef}
                  type="file"
                  accept=".glb,.gltf,.obj,.usdz"
                  style={{ display: 'none' }}
                  onChange={handleFileChange}
                />
                {selectedFile ? (
                  <div className="upload-file-selected">
                    <div className="upload-file-icon">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/>
                      </svg>
                    </div>
                    <div className="upload-file-info">
                      <div className="upload-file-name">{selectedFile.name}</div>
                      <div className="upload-file-size">{formatSize(selectedFile.size)}</div>
                    </div>
                    <button className="upload-file-clear" onClick={clearFile} title="Remove file">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                        <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
                      </svg>
                    </button>
                  </div>
                ) : (
                  <div className="upload-dropzone-prompt">
                    <div className="upload-dropzone-icon">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                        <polyline points="16 16 12 12 8 16"/><line x1="12" y1="12" x2="12" y2="21"/>
                        <path d="M20.39 18.39A5 5 0 0 0 18 9h-1.26A8 8 0 1 0 3 16.3"/>
                      </svg>
                    </div>
                    <div className="upload-dropzone-text">Drop your 3D file here</div>
                    <div className="upload-dropzone-sub">or click to browse</div>
                  </div>
                )}
              </div>

              <button
                className="upload-submit-btn"
                onClick={onUpload}
                disabled={uploading || !selectedFile}
              >
                {uploading ? (
                  <span className="upload-submit-inner">
                    <span className="upload-spinner" />
                    Uploading…
                  </span>
                ) : (
                  'Upload Room'
                )}
              </button>
            </div>
          </div>
        </section>
      )}

      {/* ── My Rooms (signed-in) ── */}
      {user && rooms.length > 0 && (
        <section className="rooms">
          <h2>My Rooms</h2>
          <div className="rooms-grid">
            {rooms.map((r) => (
              <div
                key={r.id}
                className={`room-card${activeRoom?.id === r.id ? ' active' : ''}`}
                onClick={() => selectRoom(r)}
              >
                <div className="room-card-header">
                  <strong>{r.name}</strong>
                  <button
                    className="room-delete-btn"
                    onClick={(e) => {
                      e.stopPropagation()
                      onDeleteRoom(r)
                    }}
                    title="Delete room"
                  >
                    ×
                  </button>
                </div>
                <div className="room-card-action">
                  <span>Open in Viewer</span>
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* ── Demo Rooms (always visible) ── */}
      <section className="demo-rooms">
        <h2>Demo Rooms</h2>
        {groupByCategory(DEMO_ROOMS).map(({ category, rooms: catRooms }) => (
          <div key={category} className="demo-rooms-category">
            <h3 className="demo-rooms-category-label">{category}</h3>
            <div className="demo-rooms-grid">
              {catRooms.map((room) => (
                <div
                  key={room.id}
                  className={`demo-room-card${activeRoom?.id === room.id ? ' active' : ''}`}
                  onClick={() => selectRoom(room)}
                >
                  <div className="demo-room-thumb">
                    <iframe
                      title={room.name}
                      src={`https://sketchfab.com/models/${room.sketchfabId}/embed?autostart=0&ui_controls=0&ui_infos=0&ui_inspector=0&ui_watermark=0`}
                      frameBorder="0"
                      allowFullScreen
                      allow="autoplay; fullscreen; xr-spatial-tracking"
                      tabIndex="-1"
                    />
                    <div className="demo-room-overlay">
                      <span>Open in Viewer</span>
                    </div>
                  </div>
                  <div className="demo-room-info">
                    <strong>{room.name}</strong>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}
      </section>

      {/* ── Viewer ── */}
      <section className="viewer" id="viewer-section">
        {activeRoom ? (
          activeRoom.sketchfabId ? (
            <SketchfabViewer key={activeRoom.id} modelId={activeRoom.sketchfabId} roomName={activeRoom.name} />
          ) : (
            <RoomViewer roomId={activeRoom.id} glbUrl={roomGlbUrl(activeRoom.id)} />
          )
        ) : (
          <p>Select a room above to open it in the viewer</p>
        )}
      </section>
    </div>
  )
}
