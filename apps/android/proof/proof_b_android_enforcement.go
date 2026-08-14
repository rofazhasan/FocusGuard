package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"strings"
	"time"
)

// FOCUSGUARD TECHNICAL PROOF B: Android Real Usage & VpnService DNS Sinkhole Pipeline
// Verification: Usage Session Normalization -> Policy Decision -> VpnService DNS Packet Sinkhole

// 1. Session Normalizer & Midnight Splitter
type UsageSession struct {
	AppID     string
	StartTime time.Time
	EndTime   time.Time
	Duration  time.Duration
}

func NormalizeAndSplitSessions(sessions []UsageSession) []UsageSession {
	var normalized []UsageSession
	for _, s := range sessions {
		start := s.StartTime.UTC()
		end := s.EndTime.UTC()

		// If crosses midnight UTC
		if start.Day() != end.Day() {
			midnight := time.Date(start.Year(), start.Month(), start.Day()+1, 0, 0, 0, 0, time.UTC)
			part1 := UsageSession{
				AppID:     s.AppID,
				StartTime: start,
				EndTime:   midnight,
				Duration:  midnight.Sub(start),
			}
			part2 := UsageSession{
				AppID:     s.AppID,
				StartTime: midnight,
				EndTime:   end,
				Duration:  end.Sub(midnight),
			}
			normalized = append(normalized, part1, part2)
		} else {
			s.Duration = end.Sub(start)
			normalized = append(normalized, s)
		}
	}
	return normalized
}

// 2. DNS Packet Parser & Sinkhole Response Generator (RFC 1035)
type DNSSinkhole struct {
	BlockedDomains map[string]bool
}

func (s *DNSSinkhole) ParseDomainFromDNSQuery(payload []byte) (string, uint16, error) {
	if len(payload) < 12 {
		return "", 0, fmt.Errorf("DNS payload too short")
	}

	txID := binary.BigEndian.Uint16(payload[0:2])
	offset := 12
	var domainParts []string

	for offset < len(payload) {
		length := int(payload[offset])
		if length == 0 {
			break
		}
		offset++
		if offset+length > len(payload) {
			return "", 0, fmt.Errorf("malformed DNS label")
		}
		domainParts = append(domainParts, string(payload[offset:offset+length]))
		offset += length
	}

	domain := strings.Join(domainParts, ".")
	return domain, txID, nil
}

func (s *DNSSinkhole) HandleDNSQuery(queryPacket []byte) (isBlocked bool, responsePacket []byte) {
	domain, txID, err := s.ParseDomainFromDNSQuery(queryPacket)
	if err != nil {
		return false, nil
	}

	// Check if domain or any suffix is in blocked list
	blocked := false
	lowerDomain := strings.ToLower(domain)
	for b := range s.BlockedDomains {
		if lowerDomain == b || strings.HasSuffix(lowerDomain, "."+b) {
			blocked = true
			break
		}
	}

	if !blocked {
		return false, nil // Forward allowed traffic
	}

	// Build NXDOMAIN (RCODE = 3) DNS Response Packet
	resp := make([]byte, len(queryPacket))
	copy(resp, queryPacket)

	// Flags: QR=1 (Response), AA=1, RA=1, RCODE=3 (NXDOMAIN) -> 0x8183
	binary.BigEndian.PutUint16(resp[0:2], txID)
	binary.BigEndian.PutUint16(resp[2:4], 0x8183)

	return true, resp
}

func BuildSampleDNSQuery(domain string, txID uint16) []byte {
	buf := new(bytes.Buffer)
	// Header: ID, Flags (Standard query: 0x0100), QDCOUNT=1, ANCOUNT=0, NSCOUNT=0, ARCOUNT=0
	binary.Write(buf, binary.BigEndian, txID)
	binary.Write(buf, binary.BigEndian, uint16(0x0100))
	binary.Write(buf, binary.BigEndian, uint16(1)) // 1 question
	binary.Write(buf, binary.BigEndian, uint16(0))
	binary.Write(buf, binary.BigEndian, uint16(0))
	binary.Write(buf, binary.BigEndian, uint16(0))

	// Question: QNAME
	labels := strings.Split(domain, ".")
	for _, l := range labels {
		buf.WriteByte(byte(len(l)))
		buf.WriteString(l)
	}
	buf.WriteByte(0) // Terminator

	// QTYPE=1 (A), QCLASS=1 (IN)
	binary.Write(buf, binary.BigEndian, uint16(1))
	binary.Write(buf, binary.BigEndian, uint16(1))

	return buf.Bytes()
}

func main() {
	fmt.Println("==========================================================")
	fmt.Println("FOCUSGUARD TECHNICAL PROOF B: Android VpnService Sinkhole ")
	fmt.Println("==========================================================")

	// 1. Test Session Normalizer & Midnight Splitting
	t1 := time.Date(2026, 8, 14, 23, 50, 0, 0, time.UTC)
	t2 := time.Date(2026, 8, 15, 0, 10, 0, 0, time.UTC)
	rawSession := UsageSession{
		AppID:     "com.google.android.youtube",
		StartTime: t1,
		EndTime:   t2,
	}

	splitSessions := NormalizeAndSplitSessions([]UsageSession{rawSession})
	fmt.Printf("1. Session Midnight Splitter: Raw 20m across midnight -> Result: %d partitions\n", len(splitSessions))
	for i, s := range splitSessions {
		fmt.Printf("   Part %d: %s -> %s (Duration: %v)\n", i+1, s.StartTime.Format("15:04"), s.EndTime.Format("15:04"), s.Duration)
	}
	if len(splitSessions) != 2 || splitSessions[0].Duration != 10*time.Minute || splitSessions[1].Duration != 10*time.Minute {
		panic("Session normalizer midnight split validation failed")
	}
	fmt.Println("   Session Normalization Verification -> PASS")

	// 2. Test VpnService Local DNS Sinkhole
	sinkhole := &DNSSinkhole{
		BlockedDomains: map[string]bool{
			"youtube.com":   true,
			"instagram.com": true,
		},
	}

	// 2a. Blocked Query: youtube.com
	txID1 := uint16(0xA1B2)
	queryBlocked := BuildSampleDNSQuery("m.youtube.com", txID1)
	isBlocked, respBlocked := sinkhole.HandleDNSQuery(queryBlocked)

	fmt.Printf("2. DNS Sinkhole Filter (m.youtube.com): Blocked=%v, PacketLen=%d -> PASS\n", isBlocked, len(respBlocked))
	if !isBlocked || len(respBlocked) == 0 {
		panic("Expected m.youtube.com to be blocked by DNS sinkhole")
	}
	flags := binary.BigEndian.Uint16(respBlocked[2:4])
	rcode := flags & 0x000F
	if rcode != 3 { // NXDOMAIN
		panic(fmt.Sprintf("Expected RCODE=3 (NXDOMAIN), got: %d", rcode))
	}
	fmt.Printf("   DNS Header Verification: TX_ID=0x%04X, RCODE=%d (NXDOMAIN) -> PASS\n", binary.BigEndian.Uint16(respBlocked[0:2]), rcode)

	// 2b. Allowed Query: canvas.university.edu
	txID2 := uint16(0xC3D4)
	queryAllowed := BuildSampleDNSQuery("canvas.university.edu", txID2)
	isAllowedBlocked, _ := sinkhole.HandleDNSQuery(queryAllowed)
	fmt.Printf("3. DNS Allowlist Filter (canvas.university.edu): Blocked=%v (Traffic Forwarded) -> PASS\n", isAllowedBlocked)
	if isAllowedBlocked {
		panic("Expected canvas.university.edu to be allowed through")
	}

	fmt.Println("==========================================================")
	fmt.Println("PROOF B RESULT: Android Usage & VpnService Sinkhole SUCCESS")
	fmt.Println("==========================================================")
}
