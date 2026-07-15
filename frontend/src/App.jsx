import React, { useEffect, useState } from 'react'
import { Routes, Route, useNavigate } from 'react-router-dom'
import { login, listRooms, roomGlbUrl, deleteRoom } from './api'
import HeroBg from './HeroBg'
import RoomThumbnail from './RoomThumbnail'
import Navbar from './Navbar'
import Footer from './Footer'
import LibraryBg from './LibraryBg'
import UploadPage from './UploadPage'
import RoomViewerPage from './RoomViewerPage'
import DemoViewerPage from './DemoViewerPage'

function getSavedTheme() {
  try {
    const saved = localStorage.getItem('mentis_theme')
    if (saved === 'light' || saved === 'dark') return saved
  } catch {}
  return window.matchMedia?.('(prefers-color-scheme: light)').matches ? 'light' : 'dark'
}

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
    id: 'sketchfab-da862325a9dd4e8baa638fb72b9b2325',
    name: 'Conference Room',
    category: 'Home',
    sketchfabId: 'da862325a9dd4e8baa638fb72b9b2325',
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
    id: 'sketchfab-6256d3314d5a4bd081b35d1ddc86fcd6',
    name: 'VR ClassRoom April 2021',
    category: 'Education',
    sketchfabId: '6256d3314d5a4bd081b35d1ddc86fcd6',
    author: 'BehNaM',
  },
  {
    id: 'sketchfab-ceb39aa9f61f45f6bf6d139e753fb60d',
    name: 'terrace classroom',
    category: 'Education',
    sketchfabId: 'ceb39aa9f61f45f6bf6d139e753fb60d',
    author: 'okotaru',
  },
  {
    id: 'sketchfab-026e2e9d69ed4e0892be49d439a45858',
    name: 'gym',
    category: 'Other',
    sketchfabId: '026e2e9d69ed4e0892be49d439a45858',
    author: 'Mostafa Ebrahim',
  },
  {
    id: 'sketchfab-d9b98eca8d064d0eafcd7f5484bb61ed',
    name: 'Backrooms VR',
    category: 'Other',
    sketchfabId: 'd9b98eca8d064d0eafcd7f5484bb61ed',
    author: 'carlcapu9',
  },
  {
    id: 'sketchfab-2247ed77976a40b6ae81271cd6b149c8',
    name: 'The Mystery Room',
    category: 'Other',
    sketchfabId: '2247ed77976a40b6ae81271cd6b149c8',
    author: 'The Hallwyl Museum (Hallwylska museet)',
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

function getSavedUser() {
  try { return JSON.parse(sessionStorage.getItem('mentis_user')) } catch { return null }
}
function saveUser(u)  { sessionStorage.setItem('mentis_user', JSON.stringify(u)) }
function clearUser()  { sessionStorage.removeItem('mentis_user') }

export default function App() {
  const navigate = useNavigate()
  const [theme, setTheme]           = useState(getSavedTheme)
  const [user, setUser]             = useState(getSavedUser)
  const [emailInput, setEmail]      = useState('')
  const [emailFocused, setEmailFocused] = useState(false)
  const [loginError, setLoginError] = useState(null)
  const [loggingIn, setLoggingIn]   = useState(false)
  const [rooms, setRooms]           = useState([])
  const [deleteModal, setDeleteModal] = useState(null)   // { room } | null
  const [deleteError, setDeleteError] = useState(null)
  const [deleting, setDeleting]       = useState(false)

  const emailTrimmed = emailInput.trim()
  const emailLooksValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailTrimmed)
  const showEmailHint = emailFocused || emailTrimmed.length > 0

  useEffect(() => {
    if (user) listRooms(user.user_id).then((r) => setRooms(r.rooms ?? []))
  }, [user])

  useEffect(() => {
    document.documentElement.dataset.theme = theme
    try { localStorage.setItem('mentis_theme', theme) } catch {}
  }, [theme])

  function toggleTheme() {
    setTheme((current) => (current === 'dark' ? 'light' : 'dark'))
  }

  async function doLogin(email) {
    setLoggingIn(true); setLoginError(null)
    try {
      const u = await login(email)
      saveUser(u); setUser(u)
    } catch (err) {
      setLoginError(err.message || String(err))
    } finally {
      setLoggingIn(false)
    }
  }

  function handleLogout() {
    clearUser(); setUser(null); setRooms([]); navigate('/')
  }

  function onDeleteRoom(room) {
    setDeleteError(null)
    setDeleteModal({ room })
  }

  async function confirmDelete() {
    if (!deleteModal) return
    setDeleting(true)
    setDeleteError(null)
    try {
      await deleteRoom(deleteModal.room.id)
      const roomsData = await listRooms(user.user_id)
      setRooms(roomsData.rooms ?? [])
      setDeleteModal(null)
    } catch (err) {
      setDeleteError(err.message || 'Delete failed')
    } finally {
      setDeleting(false)
    }
  }

  return (
    <div className="app">
      <Navbar user={user} onLogout={handleLogout} theme={theme} onToggleTheme={toggleTheme} />

      <Routes>
        <Route path="/upload" element={<UploadPage user={user} onUploaded={setRooms} />} />
        <Route path="/rooms/:id"       element={<RoomViewerPage />} />
        <Route path="/demo/:modelId"   element={<DemoViewerPage />} />

        <Route path="*" element={
          <>
            {/* ── Hero ── */}
            <header className="hero-header">
              <HeroBg theme={theme} />
              <div className="hero-content">
                <h1>Mentis</h1>
                <p className="hero-subtitle">Your 3D Memory Palace</p>

                {!user && (
                  <form className="login-form" onSubmit={(e) => { e.preventDefault(); if (emailInput.trim()) doLogin(emailInput.trim()) }}>
                    <div className={`login-input-wrap${emailFocused ? ' focused' : ''}${emailLooksValid ? ' valid' : ''}`}>
                      <span className="login-input-icon" aria-hidden="true">@</span>
                      <input
                        className="login-input"
                        type="email"
                        placeholder="your@email.com"
                        value={emailInput}
                        onChange={(e) => setEmail(e.target.value)}
                        onFocus={() => setEmailFocused(true)}
                        onBlur={() => setEmailFocused(false)}
                        required
                      />
                    </div>
                    <div className="login-actions">
                      <button className="login-btn" type="submit" disabled={loggingIn || !emailLooksValid}>
                        {loggingIn ? 'Signing in…' : 'Sign in'}
                      </button>
                      <button className="login-btn demo" type="button" disabled={loggingIn} onClick={() => doLogin('demo@mentis.app')}>
                        Try demo
                      </button>
                    </div>
                    <div className="login-message-row" aria-live="polite">
                      {showEmailHint && !loginError && (
                        <p className={`login-hint${emailTrimmed.length > 0 && !emailLooksValid ? ' invalid' : ''}`}>
                          {emailTrimmed.length === 0
                            ? 'Enter your email to continue'
                            : emailLooksValid
                              ? 'Looks good. Ready to sign in.'
                              : 'Use a valid email format (example@domain.com)'}
                        </p>
                      )}
                      {loginError && <p className="login-error">{loginError}</p>}
                    </div>
                  </form>
                )}
              </div>
            </header>

            {/* ── Library (My Rooms + Demo Rooms) ── */}
            <div className="library">
              <LibraryBg theme={theme} />

            {/* ── My Rooms ── */}
            {user && rooms.length > 0 && (
              <section className="rooms">
                <h2>My Rooms</h2>
                <div className="rooms-grid">
                  {rooms.map((r) => (
                    <div
                      key={r.id}
                      className="room-card"
                      onClick={() => navigate(`/rooms/${r.id}`, { state: { roomName: r.name } })}
                    >
                      <RoomThumbnail glbUrl={roomGlbUrl(r.id)} />
                      <div className="room-card-footer">
                        <strong className="room-card-name">{r.name}</strong>
                        <button
                          className="room-delete-btn"
                          onClick={(e) => { e.stopPropagation(); onDeleteRoom(r) }}
                          title="Delete room"
                        >×</button>
                      </div>
                    </div>
                  ))}
                </div>
              </section>
            )}

            {/* ── Demo Rooms ── */}
            <section className="demo-rooms">
              <h2>Demo Rooms</h2>
              {groupByCategory(DEMO_ROOMS).map(({ category, rooms: catRooms }) => (
                <div key={category} className="demo-rooms-category">
                  <h3 className="demo-rooms-category-label">{category}</h3>
                  <div className="demo-rooms-grid">
                    {catRooms.map((room) => (
                      <div
                        key={room.id}
                        className="demo-room-card"
                        onClick={() => navigate(`/demo/${room.sketchfabId}`, { state: { roomName: room.name } })}
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
                          <div className="demo-room-overlay"><span>Open in Viewer</span></div>
                        </div>
                        <div className="demo-room-info">
                          <strong>{room.name}</strong>
                          <span className="demo-room-author">by {room.author}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </section>
            </div> {/* /library */}
          </>
        } />
      </Routes>
      <Footer />

      {deleteModal && (
        <div className="modal-backdrop" onClick={() => !deleting && setDeleteModal(null)}>
          <div className="modal-card" onClick={(e) => e.stopPropagation()}>
            <h3 className="modal-title">Delete Room</h3>
            <p className="modal-body">
              Delete <strong>"{deleteModal.room.name}"</strong>? This cannot be undone.
            </p>
            {deleteError && <p className="modal-error">{deleteError}</p>}
            <div className="modal-actions">
              <button className="modal-btn modal-btn-cancel" onClick={() => setDeleteModal(null)} disabled={deleting}>
                Cancel
              </button>
              <button className="modal-btn modal-btn-delete" onClick={confirmDelete} disabled={deleting}>
                {deleting ? 'Deleting…' : 'Delete'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
