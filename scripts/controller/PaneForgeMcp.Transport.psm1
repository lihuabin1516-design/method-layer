Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:McpSessionId = $null
$script:McpRequestId = 0

function New-PaneForgeTransportException {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('transient', 'permanent', 'contract')][string]$Category = 'contract',
        [ValidateSet('not-sent', 'ambiguous', 'rejected', 'unknown')][string]$Delivery = 'unknown'
    )

    $exception = [System.Exception]::new($Message)
    $exception.Data['ControllerTransportCategory'] = $Category
    $exception.Data['ControllerDelivery'] = $Delivery
    return $exception
}

function Get-PaneForgeMcpEndpoint {
    $baseUrl = [string]$env:PANEFORGE_API_BASE_URL
    $token = [string]$env:PANEFORGE_API_TOKEN
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        throw (New-PaneForgeTransportException -Message 'PANEFORGE_API_BASE_URL is missing.' -Category permanent -Delivery not-sent)
    }
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw (New-PaneForgeTransportException -Message 'PANEFORGE_API_TOKEN is missing.' -Category permanent -Delivery not-sent)
    }
    $uri = $null
    if (-not [Uri]::TryCreate($baseUrl, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https') -or -not [System.Net.IPAddress]::IsLoopback(([System.Net.Dns]::GetHostAddresses($uri.DnsSafeHost) | Select-Object -First 1))) {
        throw (New-PaneForgeTransportException -Message 'PANEFORGE_API_BASE_URL must resolve to a loopback HTTP endpoint.' -Category permanent -Delivery not-sent)
    }
    return [pscustomobject]@{
        Uri = $baseUrl.TrimEnd('/') + '/mcp'
        Token = $token
    }
}

function ConvertFrom-PaneForgeMcpResponse {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [int]$ExpectedId = 0
    )

    $trimmed = $Content.Trim()
    $jsonPayloads = if ($trimmed.StartsWith('{')) {
        @($trimmed)
    }
    else {
        $events = $Content -split "(?:`r?`n){2,}"
        @($events | ForEach-Object {
            $data = @($_ -split "`r?`n" | Where-Object { $_ -match '^data:' } | ForEach-Object { $_ -replace '^data:\s?', '' })
            if ($data.Count -gt 0) { $data -join "`n" }
        } | Where-Object { $_ -and $_.Trim().StartsWith('{') })
    }
    $jsonPayloads = @($jsonPayloads)
    if ($jsonPayloads.Count -eq 0) {
        throw (New-PaneForgeTransportException -Message 'MCP response contains no JSON data event.' -Category contract -Delivery unknown)
    }

    try {
        $messages = @($jsonPayloads | ForEach-Object { $_ | ConvertFrom-Json })
    }
    catch {
        throw (New-PaneForgeTransportException -Message "MCP JSON event is invalid: $($_.Exception.Message)" -Category contract -Delivery unknown)
    }
    $message = if ($ExpectedId -gt 0) {
        @($messages | Where-Object { $_.PSObject.Properties.Name -contains 'id' -and [int]$_.id -eq $ExpectedId }) | Select-Object -Last 1
    }
    else {
        @($messages | Where-Object { $_.PSObject.Properties.Name -contains 'result' -or $_.PSObject.Properties.Name -contains 'error' }) | Select-Object -Last 1
    }
    if ($null -eq $message) { throw (New-PaneForgeTransportException -Message 'MCP response contains no matching JSON-RPC response.' -Category contract -Delivery unknown) }
    if ($message.PSObject.Properties.Name -contains 'error') {
        throw (New-PaneForgeTransportException -Message "MCP JSON-RPC error: $($message.error | ConvertTo-Json -Compress)" -Category permanent -Delivery rejected)
    }
    if (-not ($message.PSObject.Properties.Name -contains 'result')) {
        throw (New-PaneForgeTransportException -Message 'MCP response is missing result.' -Category contract -Delivery unknown)
    }

    $result = $message.result
    if ($result.PSObject.Properties.Name -contains 'isError' -and [bool]$result.isError) {
        $detail = @($result.content | Where-Object type -eq 'text' | ForEach-Object text) -join "`n"
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'MCP tool returned isError=true.' }
        throw (New-PaneForgeTransportException -Message $detail -Category permanent -Delivery rejected)
    }
    if ($result.PSObject.Properties.Name -contains 'structuredContent' -and $null -ne $result.structuredContent) {
        return $result.structuredContent
    }
    if ($result.PSObject.Properties.Name -contains 'content') {
        $texts = @($result.content | Where-Object type -eq 'text' | ForEach-Object text)
        if ($texts.Count -eq 0) { return $result }
        $text = $texts -join "`n"
        try { return $text | ConvertFrom-Json } catch { return $text }
    }
    return $result
}

function Invoke-PaneForgeMcpRequest {
    param(
        [Parameter(Mandatory)]$Body,
        [switch]$Notification
    )

    $endpoint = Get-PaneForgeMcpEndpoint
    $headers = @{
        Authorization = "Bearer $($endpoint.Token)"
        Accept = 'application/json, text/event-stream'
        'Content-Type' = 'application/json'
    }
    if ($script:McpSessionId) {
        $headers['Mcp-Session-Id'] = $script:McpSessionId
    }
    $json = $Body | ConvertTo-Json -Depth 100 -Compress
    try {
        $response = Invoke-WebRequest `
            -Uri $endpoint.Uri `
            -Headers $headers `
            -Method Post `
            -Body $json `
            -TimeoutSec 30 `
            -UseBasicParsing
    }
    catch {
        $status = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        if ($status -in @(408, 425, 429) -or $status -ge 500) {
            throw (New-PaneForgeTransportException -Message "MCP HTTP transient failure ($status)." -Category transient -Delivery ambiguous)
        }
        if ($status) {
            throw (New-PaneForgeTransportException -Message "MCP HTTP request rejected ($status)." -Category permanent -Delivery rejected)
        }
        $delivery = if ($_.Exception.Message -match 'refused|actively refused|No connection could be made|Name or service not known') {
            'not-sent'
        }
        else {
            'ambiguous'
        }
        throw (New-PaneForgeTransportException -Message "MCP transport failure: $($_.Exception.Message)" -Category transient -Delivery $delivery)
    }

    if (-not $script:McpSessionId) {
        $sessionHeader = @($response.Headers['Mcp-Session-Id'])
        if ($sessionHeader.Count -gt 0) {
            $script:McpSessionId = [string]$sessionHeader[0]
        }
    }
    if ($Notification) { return $null }
    $expectedId = if ($Body.ContainsKey('id')) { [int]$Body.id } else { 0 }
    return ConvertFrom-PaneForgeMcpResponse -Content ([string]$response.Content) -ExpectedId $expectedId
}

function Connect-PaneForgeMcp {
    if ($script:McpSessionId) { return }
    $script:McpRequestId++
    [void](Invoke-PaneForgeMcpRequest -Body @{
        jsonrpc = '2.0'
        id = $script:McpRequestId
        method = 'initialize'
        params = @{
            protocolVersion = '2025-03-26'
            capabilities = @{}
            clientInfo = @{ name = 'paneforge-method-layer'; version = '0.1' }
        }
    })
    if (-not $script:McpSessionId) {
        throw (New-PaneForgeTransportException -Message 'MCP initialize response omitted Mcp-Session-Id.' -Category contract -Delivery unknown)
    }
    [void](Invoke-PaneForgeMcpRequest -Notification -Body @{
        jsonrpc = '2.0'
        method = 'notifications/initialized'
        params = @{}
    })
}

function Invoke-PaneForgeMcpTool {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)]$Request
    )

    Connect-PaneForgeMcp
    $script:McpRequestId++
    return Invoke-PaneForgeMcpRequest -Body @{
        jsonrpc = '2.0'
        id = $script:McpRequestId
        method = 'tools/call'
        params = @{
            name = $Tool
            arguments = $Request
        }
    }
}

function Disconnect-PaneForgeMcp {
    $script:McpSessionId = $null
    $script:McpRequestId = 0
}

Export-ModuleMember -Function @(
    'ConvertFrom-PaneForgeMcpResponse',
    'Invoke-PaneForgeMcpTool',
    'Disconnect-PaneForgeMcp'
)
