#include "DeviceDriverSet_xxx0.h"
#include "Servo.h"
const unsigned long COMMAND_TIMEOUT_MS = 800;

DeviceDriverSet_Motor AppMotor;
unsigned long lastCommandMillis = 0;
#define ledPin 12
#define ledPin2 13
#define WING_LEFT_PIN  10
#define WING_RIGHT_PIN 11
#define WING_UP_ANGLE   60
#define WING_DOWN_ANGLE 120

Servo wingLeft;
Servo wingRight;

void stopMotors()
{
  AppMotor.DeviceDriverSet_Motor_control(direction_void, 0, direction_void, 0, control_enable);
  digitalWrite(12, HIGH);
  digitalWrite(13, HIGH);

}

void driveForward(uint8_t speed)
{
  AppMotor.DeviceDriverSet_Motor_control(direction_just, speed, direction_just, speed, control_enable);
  digitalWrite(12, LOW);
  digitalWrite(13, LOW);
}

void turnLeft(uint8_t speed)
{
  AppMotor.DeviceDriverSet_Motor_control(direction_just, speed, direction_back, speed, control_enable);
  digitalWrite(12, LOW);
  digitalWrite(13, LOW);
}

void turnRight(uint8_t speed)
{
  AppMotor.DeviceDriverSet_Motor_control(direction_back, speed, direction_just, speed, control_enable);
  digitalWrite(12, LOW);
  digitalWrite(13, LOW);
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
  pinMode(12, OUTPUT);
  pinMode(13, OUTPUT);
  digitalWrite(12, HIGH);
  digitalWrite(13, HIGH);
  pinMode(WING_LEFT_PIN, OUTPUT);
  pinMode(WING_RIGHT_PIN, OUTPUT);
}

void loop()
{
  if (Serial.available() > 0)
  {
    handleCommand(Serial.readStringUntil('\n'));
  }
  if (millis() - lastCommandMillis > COMMAND_TIMEOUT_MS)
  {
    stopMotors();
  }
}