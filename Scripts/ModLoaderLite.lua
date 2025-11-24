local tbMod = GameMain:NewMod("ModLoaderLite")

-- 常量定义
local MOD_CONFIG = {
    MOD_NAME = "ModLoaderLite",
    DLL_NAME = "ModLoaderLite.dll",
    INIT_TIMEOUT = 10,  -- 初始化超时时间（秒）
    LOAD_RETRY_COUNT = 3  -- 加载重试次数
}

-- 状态变量
local modState = {
    isInitialized = false,
    isLoaded = false,
    lastError = nil,
    retryCount = 0
}

function tbMod:OnBeforeInit()
    print(string.format("[ModLoaderLite] 开始初始化..."))
    
    -- 安全检查
    if not self:ValidateEnvironment() then
        print("[ModLoaderLite] 错误：环境验证失败")
        return false
    end
    
    -- 尝试初始化
    local success, result = pcall(function()
        return self:InitializeModLoader()
    end)
    
    if not success then
        print(string.format("[ModLoaderLite] 初始化失败: %s", tostring(result)))
        modState.lastError = result
        return false
    end
    
    modState.isInitialized = true
    print("[ModLoaderLite] 初始化完成")
    return true
end

function tbMod:OnEnter()
    print("[ModLoaderLite] 进入游戏世界")
    
    if not modState.isInitialized then
        print("[ModLoaderLite] 警告：尝试在未初始化状态下加载")
        if not self:OnBeforeInit() then
            print("[ModLoaderLite] 错误：初始化失败，无法加载")
            return
        end
    end
    
    -- 延迟加载，确保游戏完全就绪
    self:ScheduleDelayedLoad(1.0)  -- 延迟1秒加载
end

function tbMod:OnStep(dt)
    -- 可以在这里添加持续的状态检查或重试逻辑
    if not modState.isLoaded and modState.isInitialized then
        self:CheckAndRetryLoad()
    end
end

function tbMod:OnSave()
    print("[ModLoaderLite] 保存游戏数据")
    
    if not modState.isLoaded then
        print("[ModLoaderLite] 警告：尝试在未加载状态下保存")
        return
    end
    
    local success, result = pcall(function()
        CS.ModLoaderLite.MLLMain.Save()
        return true
    end)
    
    if not success then
        print(string.format("[ModLoaderLite] 保存失败: %s", tostring(result)))
        modState.lastError = result
    else
        print("[ModLoaderLite] 保存完成")
    end
end

function tbMod:NeedSyncData()
    return true
end

function tbMod:OnSyncLoad(tbData)
    print("[ModLoaderLite] 同步加载数据")
    
    if not modState.isInitialized then
        print("[ModLoaderLite] 警告：同步加载时未初始化，尝试初始化")
        if not self:OnBeforeInit() then
            print("[ModLoaderLite] 错误：初始化失败，无法同步加载")
            return
        end
    end
    
    self:ScheduleDelayedLoad(0.5)  -- 延迟0.5秒同步加载
end

function tbMod:OnSyncSave()
    print("[ModLoaderLite] 同步保存数据")
    
    if modState.isLoaded then
        local success, result = pcall(function()
            -- 这里可以添加同步保存的逻辑
            CS.ModLoaderLite.MLLMain.SyncSave()
            return true
        end)
        
        if not success then
            print(string.format("[ModLoaderLite] 同步保存失败: %s", tostring(result)))
        end
    end
end

-- 私有方法

-- 验证运行环境
function tbMod:ValidateEnvironment()
    -- 检查XLua环境
    if not xlua then
        print("[ModLoaderLite] 错误：XLua环境不可用")
        return false
    end
    
    -- 检查Mod管理器
    if not CS.ModsMgr.Instance then
        print("[ModLoaderLite] 错误：Mod管理器不可用")
        return false
    end
    
    -- 检查Lua管理器
    if not CS.XiaWorld.LuaMgr.Instance then
        print("[ModLoaderLite] 错误：Lua管理器不可用")
        return false
    end
    
    return true
end

-- 初始化Mod加载器
function tbMod:InitializeModLoader()
    -- 查找当前Mod信息
    local thisData = CS.ModsMgr.Instance:FindMod(MOD_CONFIG.MOD_NAME, nil, true)
    if not thisData then
        error(string.format("无法找到Mod: %s", MOD_CONFIG.MOD_NAME))
    end
    
    -- 获取Mod路径
    local thisPath = thisData.Path
    if not thisPath or thisPath == "" then
        error("Mod路径为空")
    end
    
    print(string.format("[ModLoaderLite] Mod路径: %s", thisPath))
    
    -- 构建DLL路径
    local mllFile = CS.System.IO.Path.Combine(thisPath, MOD_CONFIG.DLL_NAME)
    if not CS.System.IO.File.Exists(mllFile) then
        error(string.format("DLL文件不存在: %s", mllFile))
    end
    
    print(string.format("[ModLoaderLite] DLL路径: %s", mllFile))
    
    -- 加载程序集
    local asm = CS.System.Reflection.Assembly.LoadFrom(mllFile)
    if not asm then
        error("无法加载程序集")
    end
    
    print(string.format("[ModLoaderLite] 程序集加载成功: %s", asm.FullName))
    
    -- 安全访问私有字段（使用更安全的方式）
    local success = self:SafeAddAssembly(asm)
    if not success then
        error("无法将程序集添加到翻译器")
    end
    
    -- 加载依赖
    self:LoadDependencies()
    
    -- 初始化主模块
    self:InitializeMainModule()
    
    return true
end

-- 安全地添加程序集到翻译器
function tbMod:SafeAddAssembly(asm)
    local success, result = pcall(function()
        -- 方法1：尝试使用公共API（如果存在）
        if CS.XiaWorld.LuaMgr.Instance.Env and 
           CS.XiaWorld.LuaMgr.Instance.Env.translator and
           CS.XiaWorld.LuaMgr.Instance.Env.translator.assemblies then
            CS.XiaWorld.LuaMgr.Instance.Env.translator.assemblies:Add(asm)
            return true
        end
        
        -- 方法2：尝试使用反射（更安全的方式）
        local translator = CS.XiaWorld.LuaMgr.Instance.Env.translator
        if translator then
            local assembliesField = translator:GetType():GetField("assemblies", 
                CS.System.Reflection.BindingFlags.NonPublic + CS.System.Reflection.BindingFlags.Instance)
            if assembliesField then
                local assemblies = assembliesField:GetValue(translator)
                if assemblies then
                    assemblies:Add(asm)
                    return true
                end
            end
        end
        
        return false
    end)
    
    if not success then
        print(string.format("[ModLoaderLite] 添加程序集失败: %s", tostring(result)))
        return false
    end
    
    return result
end

-- 加载依赖
function tbMod:LoadDependencies()
    local success, result = pcall(function()
        CS.ModLoaderLite.MLLMain.LoadDep()
        return true
    end)
    
    if not success then
        error(string.format("加载依赖失败: %s", tostring(result)))
    end
    
    print("[ModLoaderLite] 依赖加载完成")
end

-- 初始化主模块
function tbMod:InitializeMainModule()
    local success, result = pcall(function()
        CS.ModLoaderLite.MLLMain.Init()
        return true
    end)
    
    if not success then
        error(string.format("初始化主模块失败: %s", tostring(result)))
    end
    
    print("[ModLoaderLite] 主模块初始化完成")
end

-- 延迟加载
function tbMod:ScheduleDelayedLoad(delay)
    -- 使用协程实现延迟加载
    local co = coroutine.create(function()
        -- 等待指定时间
        local elapsed = 0
        while elapsed < delay do
            elapsed = elapsed + CS.UnityEngine.Time.deltaTime
            coroutine.yield()
        end
        
        -- 执行加载
        self:ExecuteLoad()
    end)
    
    -- 启动协程
    coroutine.resume(co)
end

-- 执行加载
function tbMod:ExecuteLoad()
    if modState.isLoaded then
        print("[ModLoaderLite] 警告：尝试重复加载")
        return
    end
    
    local success, result = pcall(function()
        CS.ModLoaderLite.MLLMain.Load()
        return true
    end)
    
    if not success then
        print(string.format("[ModLoaderLite] 加载失败: %s", tostring(result)))
        modState.lastError = result
        modState.retryCount = modState.retryCount + 1
        return
    end
    
    modState.isLoaded = true
    modState.retryCount = 0
    modState.lastError = nil
    print("[ModLoaderLite] 加载完成")
end

-- 检查并重试加载
function tbMod:CheckAndRetryLoad()
    if modState.retryCount >= MOD_CONFIG.LOAD_RETRY_COUNT then
        print(string.format("[ModLoaderLite] 错误：已达到最大重试次数(%d)", MOD_CONFIG.LOAD_RETRY_COUNT))
        return
    end
    
    -- 检查是否可以进行重试
    if modState.lastError and not modState.isLoaded then
        print(string.format("[ModLoaderLite] 尝试第%d次重试加载...", modState.retryCount + 1))
        self:ScheduleDelayedLoad(2.0)  -- 延迟2秒重试
    end
end

-- 获取Mod状态信息
function tbMod:GetStatus()
    return {
        initialized = modState.isInitialized,
        loaded = modState.isLoaded,
        lastError = modState.lastError,
        retryCount = modState.retryCount,
        maxRetries = MOD_CONFIG.LOAD_RETRY_COUNT
    }
end

-- 重置Mod状态（用于调试）
function tbMod:Reset()
    modState = {
        isInitialized = false,
        isLoaded = false,
        lastError = nil,
        retryCount = 0
    }
    print("[ModLoaderLite] 状态已重置")
end

-- 调试信息
function tbMod:DebugInfo()
    local status = self:GetStatus()
    print("=== ModLoaderLite 调试信息 ===")
    print(string.format("初始化状态: %s", status.initialized and "是" or "否"))
    print(string.format("加载状态: %s", status.loaded and "是" or "否"))
    print(string.format("重试次数: %d/%d", status.retryCount, status.maxRetries))
    print(string.format("最后错误: %s", status.lastError or "无"))
    print("=============================")
end