--[[

    This module requires Packeter Server to
    function properly for web server requests.

    While you can still use it to interact with
    other servers, the requests won't benefit from
    compression and will be sent individually.

    Packeter Server:
    https://github.com/noxirity/packeter-server

--]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Base64 = require(script.Base64)

local Packeter = {
    QueuedRequests = {},
    PendingRequests = {},
    CompletedRequests = {},
	Events = {},
    PendingRequestsCount = 0,

    _LAST_REQUEST_TIME = tick(),
    _REQUEST_DELAY = 60 / 450,
    _PACKETER_URL = "https://nova-api.noxirity.com/packet",
    _STATUS = "dead",

    loggingEnabled = false,
	total_http_requests = 0
}

local function log(message)
    if Packeter.loggingEnabled then
        print(message)
    end
end

function Packeter:Initialise(configs: { PacketerUrl: string, RequestDelay: number? }?)
    assert(self._STATUS:match("^dead$"), "Packeter can only be initialised while it is dead.") -- luau parser is too strict at line 63 so we do this instead
    log("[Packeter] Initializing...")

    if configs then
        if configs.PacketerUrl then
            self._PACKETER_URL = configs.PacketerUrl
            log("[Packeter] Set Packeter URL to " .. self._PACKETER_URL)
        end
        if configs.RequestDelay then
            self._REQUEST_DELAY = configs.RequestDelay
            log("[Packeter] Set request delay to " .. tostring(self._REQUEST_DELAY))
        end
    end

    self._STATUS = "alive"
    log("[Packeter] Packeter is now alive.")

    self._INTERNAL_CONNECTION = RunService.Stepped:Connect(function()
        if
            (#self.QueuedRequests > 0 or self.PendingRequestsCount > 0)
            and tick() - self._LAST_REQUEST_TIME >= self._REQUEST_DELAY
            and self._STATUS == "alive"
        then
            self:_ProcessRequests()
        end
    end)
end

function Packeter:_ProcessRequests()
    log("[Packeter] Processing requests...")
    self._STATUS = "busy"

    local Packet = {}
    while #self.QueuedRequests > 0 do
        local request = table.remove(self.QueuedRequests, 1)
        table.insert(Packet, request)
        self.PendingRequests[request.request_id] = request
        log("[Packeter] Queued request " .. request.request_id)
    end

    self.PendingRequestsCount = #Packet
    self._LAST_REQUEST_TIME = tick()

    local EncodedPacket = Base64(HttpService:JSONEncode(Packet), "encode")
    log("[Packeter] Packet encoded and ready for transmission.")

    local function SendPacket()
        log("[Packeter] Sending packet...")
        local success, response = pcall(function()
            return HttpService:RequestAsync({
                Url = string.format("%s/%s", self._PACKETER_URL, game.JobId),
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode({ ["Packet"] = EncodedPacket }),
            })
        end)

        if success then
			self.total_http_requests += 1
            log("[Packeter] Packet sent successfully.")
        else
            warn("[Packeter] Packet send failed.")
			warn(response)
        end

        return success, response
    end

    local attempts = 0
    local success, response

    repeat
        attempts += 1
        log("[Packeter] Attempt " .. tostring(attempts) .. " to send packet.")
        success, response = SendPacket()

        if not success then
            task.wait(0.1)
        end
    until success or attempts == 3

    if success then
        self:_HandleResponse(response)
    else
        self:_HandleFailedRequests(Packet)
    end

    self._STATUS = "alive"
end

function Packeter:_HandleResponse(response)
    log("[Packeter] Handling response...")
    local ResponseBody = HttpService:JSONDecode(response.Body)
    local Results = ResponseBody["responses"]

    log("[Packeter] Received results.")
    log(ResponseBody)
    log(self.PendingRequests)

    for _, result in pairs(Results) do
        local request = self.PendingRequests[result.request_id]
        if request then
            log("[Packeter] Processing result for request " .. result.request_id)
            request.Result = {
                Code = result.response[1],
                Response = result.response[2],
            }
            self.CompletedRequests[request.request_id] = request
            self.PendingRequests[request.request_id] = nil
            self.PendingRequestsCount -= 1
			self.Events[request.request_id]:Fire()

        else
            warn("[Packeter] Received result for unknown request_id: " .. result.request_id)
        end
    end
end

function Packeter:_HandleFailedRequests(Packet)
    warn("[Packeter] Handling failed requests...")
    for _, request in ipairs(Packet) do
        request.Result = {
            Code = 500,
            Response = "Failed to send request.",
        }
        self.CompletedRequests[request.request_id] = request
        self.PendingRequests[request.request_id] = nil
        self.PendingRequestsCount -= 1
		self.Events[request.request_id]:Fire()

        warn("[Packeter] Marked request " .. request.request_id .. " as failed.")
    end
end

function Packeter:Request(
    method: "GET" | "POST" | "PUT" | "DELETE" | "PATCH",
    route: string,
    headers: { [string]: string }?,
    body: any?
): { id: string, Result: { Code: number, Response: any }? }
    local request = {
        request_id = HttpService:GenerateGUID(false),
        method = method,
        route = route,
        headers = headers,
        body = body,
    }

	self.Events[request.request_id] = Instance.new("BindableEvent")

    log("[Packeter] Request queued with ID: " .. request.request_id)
    table.insert(self.QueuedRequests, request)
	self.Events[request.request_id].Event:Wait()
	self.Events[request.request_id]:Destroy()

    local result = self.CompletedRequests[request.request_id].Result
    self.CompletedRequests[request.request_id] = nil

    if result.Code >= 200 and result.Code <= 299 then
        log("[Packeter] Request " .. request.request_id .. " completed successfully.")
        return result.Response
    else
        local errorMessage = `Request failed with status code {result.Code}: {result.Response.error}`
        warn("[Packeter] " .. errorMessage)
        error(errorMessage)
    end
end

return Packeter