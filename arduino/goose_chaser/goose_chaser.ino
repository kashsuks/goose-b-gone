#include "DeviceDriverSet_xxx0.h"

// No backward command: there's no rear-facing camera, so reversing would be
// driving blind. Only forward/turn-in-place/stop are supported.
const unsigned long COMMAND_TIMEOUT_MS = 800;

DeviceDriverSet_Motor AppMotor;
unsigned long lastCommandMillis = 0;

void stopMotors()
{
  AppMotor.DeviceDriverSet_Motor_control(direction_void, 0, direction_void, 0, control_enable);
}

void driveForward(uint8_t speed)
{
  AppMotor.DeviceDriverSet_Motor_control(direction_just, speed, direction_just, speed, control_enable);
}

void turnLeft(uint8_t speed)
{
  AppMotor.DeviceDriverSet_Motor_control(direction_just, speed, direction_back, speed, control_enable);
}

void turnRight(uint8_t speed)
{
  AppMotor.DeviceDriverSet_Motor_control(direction_back, speed, direction_just, speed, control_enable);
}

void handleCommand(String line)
{
  line.trim();
  if (line.length() == 0)
  {
    return;
  }

  char cmd = line.charAt(0);
  int spaceIndex = line.indexOf(' ');
  int speed = (spaceIndex == -1) ? 0 : line.substring(spaceIndex + 1).toInt();
  speed = constrain(speed, 0, 255);

  switch (cmd)
  {
  case 'F':
    driveForward(speed);
    break;
  case 'L':
    turnLeft(speed);
    break;
  case 'R':
    turnRight(speed);
    break;
  case 'S':
  default:
    stopMotors();
    break;
  }

  lastCommandMillis = millis();
}

void setup()
{
  Serial.begin(9600);
  Serial.setTimeout(50);
  AppMotor.DeviceDriverSet_Motor_Init();
  stopMotors();
}

void loop()
{
  if (Serial.available() > 0)
  {
    handleCommand(Serial.readStringUntil('\n'));
  }

  // Safety watchdog: if the Pi stops sending commands (crash, disconnect,
  // process exit), stop driving rather than continuing on the last command.
  if (millis() - lastCommandMillis > COMMAND_TIMEOUT_MS)
  {
    stopMotors();
  }
}
