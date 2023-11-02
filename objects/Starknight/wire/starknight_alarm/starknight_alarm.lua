function init()
  self.alarmSoundTimer = 0
  self.alarmSoundDuration = config.getParameter("alarmSoundDuration")

  self.lightColor = config.getParameter("lightColor", {27, 250, 250})
end

function update(dt)
  if not object.isInputNodeConnected(0) or object.getInputNodeLevel(0) then
    animator.setAnimationState("alarmState", "on")
	animator.setSoundVolume("alarm", 1)

    local lightWave = math.sin((self.alarmSoundTimer / self.alarmSoundDuration) * math.pi) * 0.5 + 0.5
    object.setLightColor({lightWave * self.lightColor[1], lightWave * self.lightColor[2], lightWave * self.lightColor[3]})

    if self.alarmSoundTimer <= 0 then
      animator.playSound("alarm")
      self.alarmSoundTimer = self.alarmSoundDuration
    else
      self.alarmSoundTimer = self.alarmSoundTimer - dt
    end
  else
    self.alarmSoundTimer = 0
    animator.setAnimationState("alarmState", "off")
	animator.stopAllSounds("alarm")
    object.setLightColor({0, 0, 0, 0})
  end
end
