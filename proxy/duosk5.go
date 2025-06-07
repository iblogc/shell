package main

import (
	"bufio"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	// 构建：go build -ldflags="-s -w" -o sk5 main.go
	// 脚本过期时间以及其他变量
	EXPIRE_DATE     = "2025-06-08 05:00:00"
	CONFIG_FILE     = "/usr/local/etc/xray/config.json"
	SOCKS_FILE      = "/home/socks.txt"
	XRAY_INSTALL_URL = "https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
	XRAY_VERSION    = "v1.8.4"
	START_PORT      = 10001
)

// XrayConfig represents the Xray configuration structure
type XrayConfig struct {
	Inbounds  []Inbound  `json:"inbounds"`
	Outbounds []Outbound `json:"outbounds"`
	Routing   Routing    `json:"routing"`
}

type Inbound struct {
	Port           int            `json:"port"`
	Protocol       string         `json:"protocol"`
	Settings       InboundSettings `json:"settings"`
	StreamSettings StreamSettings `json:"streamSettings"`
	Tag            string         `json:"tag"`
}

type InboundSettings struct {
	Auth     string    `json:"auth"`
	Accounts []Account `json:"accounts"`
	UDP      bool      `json:"udp"`
	IP       string    `json:"ip"`
}

type Account struct {
	User string `json:"user"`
	Pass string `json:"pass"`
}

type StreamSettings struct {
	Network string `json:"network"`
}

type Outbound struct {
	Protocol    string      `json:"protocol"`
	Settings    interface{} `json:"settings"`
	SendThrough string      `json:"sendThrough"`
	Tag         string      `json:"tag"`
}

type Routing struct {
	Rules []Rule `json:"rules"`
}

type Rule struct {
	Type        string   `json:"type"`
	InboundTag  []string `json:"inboundTag"`
	OutboundTag string   `json:"outboundTag"`
}

type NodeInfo struct {
	IP       string
	Port     int
	Username string
	Password string
}

// generateRandomString generates a random string of specified length
func generateRandomString(length int) string {
	const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, length)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	for i := range b {
		b[i] = charset[b[i]%byte(len(charset))]
	}
	return string(b)
}

// checkExpiration checks if the script has expired
func checkExpiration() error {
	fmt.Println("开始运行...")
	
	// Get timestamp from cloudflare
	resp, err := http.Get("https://www.cloudflare.com/cdn-cgi/trace")
	if err != nil {
		return fmt.Errorf("网络错误，无法获取当前时间戳: %v", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("读取响应失败: %v", err)
	}

	// Extract timestamp
	re := regexp.MustCompile(`ts=(\d+)`)
	matches := re.FindStringSubmatch(string(body))
	if len(matches) < 2 {
		return fmt.Errorf("无法解析时间戳")
	}

	timestamp, err := strconv.ParseInt(matches[1], 10, 64)
	if err != nil {
		return fmt.Errorf("时间戳转换失败: %v", err)
	}

	// Convert to Beijing time
	currentTime := time.Unix(timestamp, 0).In(time.FixedZone("CST", 8*3600))
	expireTime, _ := time.ParseInLocation("2006-01-02 15:04:05", EXPIRE_DATE, time.FixedZone("CST", 8*3600))

	if currentTime.After(expireTime) {
		return fmt.Errorf("当前脚本已过期，请联系开发者")
	}

	return nil
}

// commandExists checks if a command exists in PATH
func commandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}

// installJQ installs jq if not present
func installJQ() error {
	if commandExists("jq") {
		fmt.Println("jq 已安装")
		return nil
	}

	fmt.Println("jq 未安装，正在安装 jq...")

	// Detect OS
	if _, err := os.Stat("/etc/debian_version"); err == nil {
		// Debian/Ubuntu
		cmd := exec.Command("bash", "-c", "apt update && apt install -yq jq")
		return cmd.Run()
	} else if _, err := os.Stat("/etc/redhat-release"); err == nil {
		// RHEL/CentOS
		cmd := exec.Command("yum", "install", "-y", "epel-release", "jq")
		return cmd.Run()
	}

	return fmt.Errorf("无法确定系统发行版，请手动安装 jq")
}

// installXray installs Xray if not present
func installXray() error {
	if commandExists("xray") {
		fmt.Println("Xray 已安装")
		return nil
	}

	fmt.Println("Xray 未安装，正在安装 Xray...")

	cmd := exec.Command("bash", "-c", fmt.Sprintf("curl -L %s | bash -s install --version %s", XRAY_INSTALL_URL, XRAY_VERSION))
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("Xray 安装失败: %v", err)
	}

	fmt.Println("Xray 安装完成")
	return nil
}

// getPublicIPv4 gets all public IPv4 addresses
func getPublicIPv4() ([]string, error) {
	var publicIPs []string

	// Get all network interfaces
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}

	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}

		for _, addr := range addrs {
			if ipNet, ok := addr.(*net.IPNet); ok && !ipNet.IP.IsLoopback() {
				if ipNet.IP.To4() != nil {
					ip := ipNet.IP.String()
					// Check if it's a public IP
					if isPublicIP(ip) {
						publicIPs = append(publicIPs, ip)
					}
				}
			}
		}
	}

	return publicIPs, nil
}

// isPublicIP checks if an IP is public
func isPublicIP(ip string) bool {
	parsedIP := net.ParseIP(ip)
	if parsedIP == nil {
		return false
	}

	// Check for private IP ranges
	privateRanges := []string{
		"127.0.0.0/8",    // loopback
		"10.0.0.0/8",     // private
		"172.16.0.0/12",  // private
		"192.168.0.0/16", // private
		"169.254.0.0/16", // link-local
	}

	for _, cidr := range privateRanges {
		_, network, _ := net.ParseCIDR(cidr)
		if network.Contains(parsedIP) {
			return false
		}
	}

	return true
}

// ensureSocksFileExists creates socks.txt if it doesn't exist
func ensureSocksFileExists() error {
	if _, err := os.Stat(SOCKS_FILE); os.IsNotExist(err) {
		fmt.Println("socks.txt 文件不存在，正在创建...")
		file, err := os.Create(SOCKS_FILE)
		if err != nil {
			return err
		}
		file.Close()
	}
	return nil
}

// saveNodeInfo saves node information to file and prints it
func saveNodeInfo(node NodeInfo) error {
	// Print node info with colors
	fmt.Printf(" IP: \033[32m%s\033[0m 端口: \033[32m%d\033[0m 用户名: \033[32m%s\033[0m 密码: \033[32m%s\033[0m\n",
		node.IP, node.Port, node.Username, node.Password)

	// Save to file
	file, err := os.OpenFile(SOCKS_FILE, os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	defer file.Close()

	_, err = fmt.Fprintf(file, "%s %d %s %s\n", node.IP, node.Port, node.Username, node.Password)
	return err
}

// configureXray configures Xray with multiple IPs
func configureXray() error {
	publicIPs, err := getPublicIPv4()
	if err != nil {
		return fmt.Errorf("获取公网IP失败: %v", err)
	}

	if len(publicIPs) == 0 {
		return fmt.Errorf("未找到额外IP地址")
	}

	fmt.Printf("找到的公网 IPv4 地址: %v\n", publicIPs)

	// Create initial config
	config := XrayConfig{
		Inbounds:  []Inbound{},
		Outbounds: []Outbound{},
		Routing: Routing{
			Rules: []Rule{},
		},
	}

	// Configure each IP
	port := START_PORT
	for _, ip := range publicIPs {
		fmt.Printf("正在配置 IP: %s 端口: %d\n", ip, port)

		username := generateRandomString(8)
		password := generateRandomString(8)

		// Create inbound
		inbound := Inbound{
			Port:     port,
			Protocol: "socks",
			Settings: InboundSettings{
				Auth: "password",
				Accounts: []Account{
					{User: username, Pass: password},
				},
				UDP: true,
				IP:  "0.0.0.0",
			},
			StreamSettings: StreamSettings{
				Network: "tcp",
			},
			Tag: fmt.Sprintf("in-%d", port),
		}

		// Create outbound
		outbound := Outbound{
			Protocol:    "freedom",
			Settings:    map[string]interface{}{},
			SendThrough: ip,
			Tag:         fmt.Sprintf("out-%d", port),
		}

		// Create routing rule
		rule := Rule{
			Type:        "field",
			InboundTag:  []string{fmt.Sprintf("in-%d", port)},
			OutboundTag: fmt.Sprintf("out-%d", port),
		}

		config.Inbounds = append(config.Inbounds, inbound)
		config.Outbounds = append(config.Outbounds, outbound)
		config.Routing.Rules = append(config.Routing.Rules, rule)

		// Save node info
		node := NodeInfo{
			IP:       ip,
			Port:     port,
			Username: username,
			Password: password,
		}
		if err := saveNodeInfo(node); err != nil {
			return fmt.Errorf("保存节点信息失败: %v", err)
		}

		port++
	}

	// Write config file
	configData, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return fmt.Errorf("序列化配置失败: %v", err)
	}

	if err := os.WriteFile(CONFIG_FILE, configData, 0644); err != nil {
		return fmt.Errorf("写入配置文件失败: %v", err)
	}

	fmt.Println("Xray 配置完成")
	return nil
}

// restartXray restarts the Xray service
func restartXray() error {
	fmt.Println("正在重启 Xray 服务...")

	// Restart service
	cmd := exec.Command("systemctl", "restart", "xray")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("Xray 服务重启失败: %v", err)
	}

	// Enable service
	cmd = exec.Command("systemctl", "enable", "xray")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("启用 Xray 服务失败: %v", err)
	}

	fmt.Println("Xray 服务已重启")
	return nil
}

// readUserInput reads user input for confirmation
func readUserInput(prompt string) string {
	fmt.Print(prompt)
	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	return strings.TrimSpace(input)
}

func main() {
	fmt.Println("站群多IP源进源出节点脚本")
	fmt.Println("作者: sky22333")
	fmt.Println()

	// Check expiration
	if err := checkExpiration(); err != nil {
		fmt.Printf("错误: %v\n", err)
		os.Exit(1)
	}

	// Ensure socks file exists
	if err := ensureSocksFileExists(); err != nil {
		fmt.Printf("创建socks文件失败: %v\n", err)
		os.Exit(1)
	}

	// Install jq
	if err := installJQ(); err != nil {
		fmt.Printf("安装jq失败: %v\n", err)
		os.Exit(1)
	}

	// Install Xray
	if err := installXray(); err != nil {
		fmt.Printf("安装Xray失败: %v\n", err)
		os.Exit(1)
	}

	// Configure Xray
	if err := configureXray(); err != nil {
		fmt.Printf("配置Xray失败: %v\n", err)
		os.Exit(1)
	}

	// Restart Xray
	if err := restartXray(); err != nil {
		fmt.Printf("重启Xray失败: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("部署完成，所有节点信息已保存到 %s\n", SOCKS_FILE)
}
