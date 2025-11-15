local tbMod = GameMain:NewMod("ModLoaderLite")


function tbMod:OnBeforeInit()
  xlua.private_accessible(CS.XLua.LuaEnv)
  xlua.private_accessible(CS.XLua.ObjectTranslator)
  local thisData = CS.ModsMgr.Instance:FindMod("ModLoaderLite", nil, true)
  local thisPath = thisData.Path
  local mllFile = CS.System.IO.Path.Combine(thisPath, "ModLoaderLite.dll")
  local asm = CS.System.Reflection.Assembly.LoadFrom(mllFile)
  CS.XiaWorld.LuaMgr.Instance.Env.translator.assemblies:Add(asm)
  CS.ModLoaderLite.MLLMain.LoadDep()
  CS.ModLoaderLite.MLLMain.Init()
end

function tbMod:OnEnter()
  CS.ModLoaderLite.MLLMain.Load()
end

function tbMod:OnSave()
  CS.ModLoaderLite.MLLMain.Save()
end

function tbMod:NeedSyncData()--切换地图的时候是否会同步数据，请谨慎使用
	 return true
end

function tbMod:OnSyncLoad(tbData)	--切换地图的时候载入的数据
	CS.ModLoaderLite.MLLMain.Load()
end

function tbMod:OnSyncSave()	--切换地图时传输的数据

end