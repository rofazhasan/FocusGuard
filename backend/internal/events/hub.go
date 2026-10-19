package events

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/focusguard/focusguard/backend/internal/auth"
	"github.com/focusguard/focusguard/backend/pkg/logger"
)

const (
	// writeWait is the time allowed to write a message to the peer.
	writeWait = 10 * time.Second

	// pongWait is the time allowed to read the next pong message from the peer.
	pongWait = 60 * time.Second

	// pingPeriod is the period to send pings to peer. Must be less than pongWait.
	pingPeriod = (pongWait * 9) / 10

	// maxMessageSize is the maximum message size allowed from peer (512KB).
	maxMessageSize = 512 * 1024
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		if origin == "" {
			return true // Native apps (macOS, Android TUN, CLI) do not send Origin
		}
		// Allow browser extension runtimes
		if strings.HasPrefix(origin, "chrome-extension://") || strings.HasPrefix(origin, "moz-extension://") {
			return true
		}
		// Allow local development endpoints
		if strings.HasPrefix(origin, "http://localhost") || strings.HasPrefix(origin, "http://127.0.0.1") ||
			strings.HasPrefix(origin, "https://localhost") || strings.HasPrefix(origin, "https://127.0.0.1") {
			return true
		}
		// Allow configured production origins
		allowed := os.Getenv("ALLOWED_ORIGINS")
		if allowed != "" {
			for _, o := range strings.Split(allowed, ",") {
				if strings.TrimSpace(o) == origin {
					return true
				}
			}
		}
		// Allow all only in non-production environments
		if os.Getenv("ENV") != "production" {
			return true
		}
		return false
	},
}

type EventMessage struct {
	Event   string      `json:"event"`
	Payload interface{} `json:"payload"`
}

type Client struct {
	UserID    uuid.UUID
	DeviceID  uuid.UUID
	Conn      *websocket.Conn
	Send      chan EventMessage
	closeOnce sync.Once
}

func (c *Client) Close() {
	c.closeOnce.Do(func() {
		_ = c.Conn.Close()
	})
}

type Hub struct {
	clients                map[*Client]bool
	userMap                map[uuid.UUID]map[*Client]bool
	deviceMap              map[uuid.UUID]map[*Client]bool
	lastExtensionHeartbeat map[uuid.UUID]time.Time
	register               chan *Client
	unregister             chan *Client
	broadcast              chan struct {
		UserID  uuid.UUID
		Message EventMessage
	}
	db *sql.DB
	mu sync.Mutex
}

func NewHub() *Hub {
	return &Hub{
		clients:                make(map[*Client]bool),
		userMap:                make(map[uuid.UUID]map[*Client]bool),
		deviceMap:              make(map[uuid.UUID]map[*Client]bool),
		lastExtensionHeartbeat: make(map[uuid.UUID]time.Time),
		register:               make(chan *Client, 64),
		unregister:             make(chan *Client, 64),
		broadcast: make(chan struct {
			UserID  uuid.UUID
			Message EventMessage
		}, 256),
	}
}

func (h *Hub) SetDB(db *sql.DB) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.db = db
}

func (h *Hub) UpdateExtensionHeartbeat(userID uuid.UUID) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.lastExtensionHeartbeat == nil {
		h.lastExtensionHeartbeat = make(map[uuid.UUID]time.Time)
	}
	h.lastExtensionHeartbeat[userID] = time.Now()
}

func (h *Hub) IsExtensionActive(userID uuid.UUID, maxAge time.Duration) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.lastExtensionHeartbeat == nil {
		return false
	}
	last, exists := h.lastExtensionHeartbeat[userID]
	if !exists {
		return false
	}
	return time.Since(last) <= maxAge
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			if _, exists := h.userMap[client.UserID]; !exists {
				h.userMap[client.UserID] = make(map[*Client]bool)
			}
			h.userMap[client.UserID][client] = true

			if client.DeviceID != uuid.Nil {
				if _, exists := h.deviceMap[client.DeviceID]; !exists {
					h.deviceMap[client.DeviceID] = make(map[*Client]bool)
				}
				h.deviceMap[client.DeviceID][client] = true
			}
			h.mu.Unlock()
			logger.Info("WebSocket client registered", "userID", client.UserID, "deviceID", client.DeviceID)

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				close(client.Send)
				if uClients, exists := h.userMap[client.UserID]; exists {
					delete(uClients, client)
					if len(uClients) == 0 {
						delete(h.userMap, client.UserID)
					}
				}
				if client.DeviceID != uuid.Nil {
					if dClients, exists := h.deviceMap[client.DeviceID]; exists {
						delete(dClients, client)
						if len(dClients) == 0 {
							delete(h.deviceMap, client.DeviceID)
						}
					}
				}
			}
			h.mu.Unlock()
			logger.Info("WebSocket client unregistered", "userID", client.UserID)

		case req := <-h.broadcast:
			h.mu.Lock()
			if clients, exists := h.userMap[req.UserID]; exists {
				for client := range clients {
					select {
					case client.Send <- req.Message:
					default:
						close(client.Send)
						delete(h.clients, client)
						delete(clients, client)
						client.Close()
					}
				}
			}
			h.mu.Unlock()
		}
	}
}

func (h *Hub) BroadcastToUser(userID uuid.UUID, msg EventMessage) {
	h.broadcast <- struct {
		UserID  uuid.UUID
		Message EventMessage
	}{UserID: userID, Message: msg}
}

func (h *Hub) DisconnectDevice(deviceID uuid.UUID) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if clients, exists := h.deviceMap[deviceID]; exists {
		for client := range clients {
			_ = client.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			_ = client.Conn.WriteJSON(EventMessage{
				Event: "DEVICE_REVOKED",
				Payload: map[string]interface{}{
					"deviceId": deviceID.String(),
					"message":  "Device access permanently revoked by owner",
				},
			})
			client.Close()
			delete(h.clients, client)
			if uClients, uExists := h.userMap[client.UserID]; uExists {
				delete(uClients, client)
			}
		}
		delete(h.deviceMap, deviceID)
	}
}

func (h *Hub) ServeWS(tokenService *auth.TokenService, db *sql.DB, w http.ResponseWriter, r *http.Request) {
	tokenStr := r.URL.Query().Get("token")
	if tokenStr == "" {
		tokenStr = r.Header.Get("Sec-WebSocket-Protocol")
	}

	isProd := os.Getenv("ENV") == "production" || os.Getenv("NODE_ENV") == "production"

	var claims *auth.Claims
	var err error
	if tokenStr != "" {
		claims, err = tokenService.ValidateToken(tokenStr)
		if err != nil {
			if !isProd && (strings.HasPrefix(tokenStr, "FG-") || strings.HasPrefix(tokenStr, "ext_")) {
				claims = nil // Allow fallback to demo user in local development only
			} else {
				http.Error(w, `{"error":"Invalid or expired token"}`, http.StatusUnauthorized)
				return
			}
		}
	} else if isProd {
		http.Error(w, `{"error":"Authorization token required"}`, http.StatusUnauthorized)
		return
	}

	// Fallback to default owner user ONLY for local non-production development
	if claims == nil {
		if isProd {
			http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
			return
		}
		defaultUserID := uuid.MustParse("00000000-0000-0000-0000-000000000001")
		claims = &auth.Claims{
			UserID: defaultUserID,
			Email:  "demo@focusguard.local",
			Role:   "OWNER",
		}
	}

	deviceID := claims.DeviceID

	// Check if device is revoked in database
	if deviceID != uuid.Nil && db != nil {
		var status string
		err := db.QueryRowContext(r.Context(), `SELECT status FROM devices WHERE id = $1`, deviceID.String()).Scan(&status)
		if err == nil && strings.ToUpper(status) == "REVOKED" {
			http.Error(w, `{"error":"Device is revoked"}`, http.StatusForbidden)
			return
		}
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		logger.Error("Failed to upgrade WebSocket connection", "error", err)
		return
	}

	client := &Client{
		UserID:   claims.UserID,
		DeviceID: deviceID,
		Conn:     conn,
		Send:     make(chan EventMessage, 256),
	}

	h.register <- client

	go client.writePump(h)
	go client.readPump(h)
}

func (c *Client) readPump(h *Hub) {
	defer func() {
		h.unregister <- c
		c.Close()
	}()

	c.Conn.SetReadLimit(maxMessageSize)
	_ = c.Conn.SetReadDeadline(time.Now().Add(pongWait))
	c.Conn.SetPongHandler(func(string) error {
		_ = c.Conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, msg, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}

		var raw map[string]interface{}
		if err := json.Unmarshal(msg, &raw); err == nil {
			msgType, _ := raw["type"].(string)
			platform, _ := raw["platform"].(string)
			devIDStr, _ := raw["deviceId"].(string)
			if msgType == "HEARTBEAT" || platform == "WEB_EXTENSION" {
				h.UpdateExtensionHeartbeat(c.UserID)
			}
			if platform == "WEB_EXTENSION" || msgType == "REGISTER_DEVICE" {
				h.mu.Lock()
				db := h.db
				h.mu.Unlock()
				if db != nil {
					targetID := devIDStr
					if targetID == "" {
						targetID = "5028eea4-8da8-431a-91c7-d637a6837f9f"
					}
					_, err := db.Exec(`INSERT INTO devices (id, user_id, device_name, platform, client_type, os_version, status, role, policy_version, created_at, updated_at)
					                VALUES ($1, $2, 'Google Chrome Extension', 'WEB_EXTENSION', 'EXTENSION', 'Chrome MV3', 'ACTIVE', 'MANAGED', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
					                ON CONFLICT(id) DO UPDATE SET updated_at = CURRENT_TIMESTAMP, status = 'ACTIVE'`,
						targetID, c.UserID.String())
					if err != nil {
						logger.Error("Failed to register/update extension device", "error", err)
					}
				}
			}
		}
	}
}

func (c *Client) writePump(h *Hub) {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.Close()
	}()

	for {
		select {
		case msg, ok := <-c.Send:
			_ = c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// Hub closed the channel
				_ = c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			data, err := json.Marshal(msg)
			if err != nil {
				continue
			}
			if err := c.Conn.WriteMessage(websocket.TextMessage, data); err != nil {
				return
			}

		case <-ticker.C:
			_ = c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
