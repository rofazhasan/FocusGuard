package events

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/focusguard/focusguard/backend/internal/auth"
	"github.com/focusguard/focusguard/backend/pkg/logger"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all cross-device clients
	},
}

type EventMessage struct {
	Event   string      `json:"event"`
	Payload interface{} `json:"payload"`
}

type Client struct {
	UserID uuid.UUID
	Conn   *websocket.Conn
	Send   chan EventMessage
}

type Hub struct {
	clients                map[*Client]bool
	userMap                map[uuid.UUID]map[*Client]bool
	lastExtensionHeartbeat map[uuid.UUID]time.Time
	register               chan *Client
	unregister             chan *Client
	broadcast              chan struct {
		UserID  uuid.UUID
		Message EventMessage
	}
	mu sync.Mutex
}

func NewHub() *Hub {
	return &Hub{
		clients:                make(map[*Client]bool),
		userMap:                make(map[uuid.UUID]map[*Client]bool),
		lastExtensionHeartbeat: make(map[uuid.UUID]time.Time),
		register:               make(chan *Client),
		unregister:             make(chan *Client),
		broadcast: make(chan struct {
			UserID  uuid.UUID
			Message EventMessage
		}),
	}
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
			h.mu.Unlock()
			logger.Info("WebSocket client registered", "userID", client.UserID)

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

func (h *Hub) ServeWS(tokenService *auth.TokenService, w http.ResponseWriter, r *http.Request) {
	tokenStr := r.URL.Query().Get("token")
	if tokenStr == "" {
		tokenStr = r.Header.Get("Sec-WebSocket-Protocol")
	}

	var claims *auth.Claims
	var err error
	if tokenStr != "" {
		claims, err = tokenService.ValidateToken(tokenStr)
	}

	// Fallback to default owner user for zero-friction local extension connection
	if claims == nil || err != nil {
		defaultUserID := uuid.MustParse("00000000-0000-0000-0000-000000000001")
		claims = &auth.Claims{
			UserID: defaultUserID,
			Email:  "demo@focusguard.local",
		}
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		logger.Error("Failed to upgrade WebSocket connection", "error", err)
		return
	}

	client := &Client{
		UserID: claims.UserID,
		Conn:   conn,
		Send:   make(chan EventMessage, 256),
	}

	h.register <- client

	go client.writePump()
	go client.readPump(h)
}

func (c *Client) readPump(h *Hub) {
	defer func() {
		h.unregister <- c
		c.Conn.Close()
	}()

	for {
		_, msg, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}

		var raw map[string]interface{}
		if err := json.Unmarshal(msg, &raw); err == nil {
			msgType, _ := raw["type"].(string)
			platform, _ := raw["platform"].(string)
			if msgType == "HEARTBEAT" || platform == "WEB_EXTENSION" {
				h.UpdateExtensionHeartbeat(c.UserID)
			}
		}
	}
}

func (c *Client) writePump() {
	defer c.Conn.Close()

	for msg := range c.Send {
		data, err := json.Marshal(msg)
		if err != nil {
			continue
		}
		if err := c.Conn.WriteMessage(websocket.TextMessage, data); err != nil {
			break
		}
	}
}
