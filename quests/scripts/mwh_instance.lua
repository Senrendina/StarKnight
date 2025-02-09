--继奥法xPR integration的守护团大剑和尚未发售的军备工坊的插件系统后本人的又一力作
--支持instance类任务在副本内存在多目标时进行引导的脚本
require "/scripts/util.lua"
require "/quests/scripts/questutil.lua"
require "/quests/scripts/portraits.lua"

--初始化
function init()
  --设置参数
  self.descriptions = config.getParameter("descriptions")

  self.warpEntity = config.getParameter("warpEntityUid")
  self.warpAction = config.getParameter("warpAction")
  self.warpDialog = config.getParameter("warpDialog")

  self.turnInEntity = config.getParameter("turnInEntityUid")

  --self.target *list* 副本内的所有目标的列表 在实际任务过程中依照填写顺序进行判定
  self.targets = config.getParameter("targets")
  --self.targetAmount *double* 所有的目标数量
  self.targetAmount = #self.targets

  --任务目标判定变量 该变量无需在玩家传送时储存 故直接以全局变量的形式写在init
  if self.targetAmount > 1 then
    self.targetIndex = 1
  else self.targetIndex = 0
  end

  -- self.checkpoints *list* 副本内所有的检查点
  self.checkpoints = config.getParameter("checkpoints")

  self.goalEntity = self.targets[self.targetAmount].targetEntityUid

  self.turnInEntity = config.getParameter("turnInEntityUid")

  --设置肖像
  setPortraits()

  --任务三阶段 进入副本 寻找目标 交任务
  self.stages = {
    enterInstance,
    findTarget,
    turnIn
  }

  --设置当前任务阶段 默认从enterInstance开始
  storage.stage = storage.stage or 1
  storage.goalSavedIndex = storage.goalSavedIndex or 0
  --设置任务的有限状态机
  --话说什么是有限状态机 (Finite State Machine)
  self.state = FSM:new()
  self.state:set(self.stages[storage.stage])
end

--我也不知道什么用就干脆留着了 貌似是什么关联任务
function questStart()
  local associatedMission = config.getParameter("associatedMission")
  if associatedMission then
    player.enableMission(associatedMission)
  end
end

--update的作用就是不断update状态机了
function update(dt)
  self.state:update()
end

--不知道有什么用 但感觉很重要而且貌似和互动有关 就留着了
function questInteract(entityId)
  if self.onInteract then
    return self.onInteract(entityId)
  end
end

--任务完成时的指令
function questComplete()
  setPortraits()

  questutil.questCompleteActions()
end

--任务第一步：进入副本
function enterInstance(dt)
  --隐藏任务指针
  quest.setCompassDirection(nil)
  --任务描述更新为进入副本的描述
  quest.setObjectiveList({
    {self.descriptions.enterInstance, false}
  })
  --设置蓝色指引箭头
  quest.setParameter("warpentity", {type = "entity", uniqueId = self.warpEntity})
  quest.setIndicators({"warpentity"})

  --玩家互动时执行
  self.onInteract = function(entityId)
    --如果玩家互动的对象的uid正是给定的uid 则
    if world.entityUniqueId(entityId) == self.warpEntity then
      --若没有弹出传送确认 则
      if not self.warpConfirmation then
        --弹出对应的传送窗口
        local dialogConfig = root.assetJson(self.warpDialog)
        dialogConfig.sourceEntityId = entityId
        self.warpConfirmation = player.confirm(dialogConfig)
      end
      return true
    end
  end

  --设置跟踪进入副本的对象的uid和任务交付目标的uid
  local findWarpEntity = util.uniqueEntityTracker(self.warpEntity, 0.5)
  local findGoalEntity = util.uniqueEntityTracker(self.goalEntity, 1.0)

  --如果尚处在任务的第一步 则
  while storage.stage == 1 do
    --此时如果存在可以互动进入副本的对象 将指针指向该目标
    questutil.pointCompassAt(findWarpEntity())

    --如果找到了任务交付目标的uid 进入任务的第二步
    if findGoalEntity() then
      storage.stage = 2
    end

    if findWarpEntity() and not findGoalEntity() then
      storage.goalSavedIndex = 0
    end

    --传送相关
    if self.warpConfirmation and self.warpConfirmation:finished() then
      if self.warpConfirmation:result() then
        --如果warpAction是字符串 直接传送 使用激光弹射作为传送动画
        --如果是table 则将第一个字符串视作传送行为 第二个字符串视作传送动画具体设置 第三个布尔值决定是否在传送时召唤机甲
        if type(self.warpAction) == "string" then
          player.warp(self.warpAction, "beam")
        elseif type(self.warpAction) == "table" then
          player.warp(self.warpAction[1], self.warpAction[2], self.warpAction[3])
        end
        storage.goalSavedIndex = 0
      end
      self.warpConfirmation = nil
    end

    --挂起
    coroutine.yield()
  end

  --设置任务步骤
  self.state:set(self.stages[storage.stage])
end

--任务第二步：设置目标
function findTarget(dt)
  --隐藏任务指针
  quest.setCompassDirection(nil)
  quest.setIndicators({})
  local findGoalEntity = util.uniqueEntityTracker(self.goalEntity, 1.0)

  --定位所有目标
  --如果这一部分写在while里会出问题 所以单独写出来
  local targetEntity = {}
  for i in pairs(self.targets) do
    targetEntity[i] = util.uniqueEntityTracker(self.targets[i].targetEntityUid, 0.5)
    if self.targets[i].targetTrigger == "interact" then
      self.targets[i].index = i
    end
  end

  --定位所有复活点
  local checkpointEntity = {}
  if self.checkpoints then
    for v in pairs(self.checkpoints) do
      checkpointEntity[v] = util.uniqueEntityTracker(self.checkpoints[v].checkpointUid, 0.5)
    end
  end

  --如果尚处在任务的第二步 则
  while storage.stage == 2 do 
    --如果并非所有任务目标都被达成
    if self.targetAmount >= self.targetIndex then
      --确定当前目标编号
      local index = self.targetIndex
      --定位当前目标UID及其坐标
      local targetPosition = targetEntity[index]()

      --若该任务目标的UID存在
      if targetPosition then
        --设置任务目标描述
        quest.setObjectiveList({
          {self.targets[index].description, false}
        })
        --若设置了指向标 则会有一个蓝色小箭头悬浮在目标上方
        if self.targets[index].indicator == true then
          quest.setParameter("goalentity", {type = "entity", uniqueId = self.targets[index].targetEntityUid})
          quest.setIndicators({"goalentity"})
        else
          quest.setIndicators({})
        end

        --若设置了指针跟踪 则任务指针会指向该UID所在的坐标
        if self.targets[index].track == true then 
          questutil.pointCompassAt(targetPosition)
        else quest.setCompassDirection(nil)
        end

        --若该目标的触发方式是靠近触发
        if self.targets[index].targetTrigger == "proximity" then
          --判定玩家和目标的距离 若在距离内 该目标视作完成
          if world.magnitude(mcontroller.position(), targetPosition) < self.targets[index].proximityRange then
            self.targetIndex = self.targetIndex + 1
            storage.goalSavedIndex = self.targetIndex
          end
        --若该目标的触发方式是互动触发
        elseif self.targets[index].targetTrigger == "interact" then
          self.onInteract = function(entityId)
            --若互动的对象的UID和目标UID相同 该目标视作完成
            if world.entityUniqueId(entityId) == self.targets[index].targetEntityUid then
              --这样写而不是直接写 self.targetIndex = self.targetIndex + 1 是为了防止在极快速互动的情况下直接跳目标阶段的问题
              if self.targetIndex <= self.targets[index].index then
                self.targetIndex = self.targets[index].index + 1
                storage.goalSavedIndex = self.targetIndex
              end
            end
          end
        end
      end

      --如果设置了复活点
      if self.checkpoints then
        --判断是否靠近一个复活点 如果是 将目标进度设置为该复活点所设置的进度
        for u = 1, #self.checkpoints do
          local checkpointPos = checkpointEntity[u]()
          if checkpointPos then
            if world.magnitude(mcontroller.position(), checkpointPos) < 20 then
              if self.checkpoints[u].index then
                if self.checkpoints[u].index > index then
                  self.targetIndex = self.checkpoints[u].index
                end
              else
                self.targetIndex = storage.goalSavedIndex
              end
            end
          end
        end
      end

      --如果玩家中途离开了副本 重置回第一步
      if findGoalEntity() == nil then
        storage.stage = 1
      end

    --如果所有目标都已达成 进入最后一步
    else
      storage.stage = 3
    end

    --挂起
    coroutine.yield()
  end

  --设置任务步骤
  self.state:set(self.stages[storage.stage])
end

--任务第三步：交付任务
function turnIn()
  --隐藏任务指针
  quest.setCompassDirection(nil)
  --设置任务交付描述
  quest.setObjectiveList({
    {self.descriptions.turnIn, false}
  })
  quest.setIndicators({})
  self.onInteract = nil

  --如果设置了交付任务的UID
  if self.turnInEntity then
    --设置任务可交付
    quest.setCanTurnIn(true)
    --如果存在交付任务的UID
    local findTurnInEntity = util.uniqueEntityTracker(self.turnInEntity, 0.5)
    --指针指向可完成任务的目标
    while true do
      questutil.pointCompassAt(findTurnInEntity())
      coroutine.yield()
    end
  --没设置交付任务UID的情况下直接完成任务
  else
    quest.complete()
  end
end