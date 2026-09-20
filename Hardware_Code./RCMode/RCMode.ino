#include <IRremote.hpp>
#include <Servo.h>

#define IR_RECEIVE_PIN 9

#define PWMA 5   
#define AIN1 7   
#define PWMB 6   
#define BIN1 8   
#define STBY 3   

#define WING_LEFT_PIN  10
#define WING_RIGHT_PIN 11

#define WING_UP_ANGLE   60
#define WING_DOWN_ANGLE 120

Servo wingLeft;
Servo wingRight;
bool wingsUp = false;

#define aRECV_upper 0xB946FF00
#define aRECV_lower 0xEA15FF00
#define aRECV_Left  0xBB44FF00
#define aRECV_right 0xBC43FF00
#define aRECV_ok    0xBF40FF00

int carSpeed = 200; 

unsigned long lastPressedCode = 0;

const unsigned long IR_TIMEOUT_MS = 200;
unsigned long lastIRTime = 0;
bool carMoving = false;

bool okHeld = false;
unsigned long lastFlapTime = 0;
const unsigned long FLAP_INTERVAL_MS = 250; 

void setup() {
  Serial.begin(115200);
  IrReceiver.begin(IR_RECEIVE_PIN, ENABLE_LED_FEEDBACK);

  pinMode(PWMA, OUTPUT);
  pinMode(PWMB, OUTPUT);
  pinMode(AIN1, OUTPUT);
  pinMode(BIN1, OUTPUT);
  pinMode(STBY, OUTPUT);

  wingLeft.attach(WING_LEFT_PIN);
  wingRight.attach(WING_RIGHT_PIN);
  wingLeft.write(WING_DOWN_ANGLE);
  wingRight.write(180 - WING_DOWN_ANGLE);

  stopCar();
  Serial.println("Ready. Point the remote at the IR receiver.");
  pinMode(12, OUTPUT);
  pinMode(13, OUTPUT);
  digitalWrite(12, LOW);
  digitalWrite(13, LOW);
}

void loop() 
{
  if (IrReceiver.decode()) 
  {
    bool isCorrupted = (IrReceiver.decodedIRData.flags & IRDATA_FLAGS_WAS_OVERFLOW);
    bool isNec = (IrReceiver.decodedIRData.protocol == NEC);
    bool isRepeat = (IrReceiver.decodedIRData.flags & IRDATA_FLAGS_IS_REPEAT);

    if (!isNec || isCorrupted) 
    {
      IrReceiver.resume();
      return; 
    }

    lastIRTime = millis();

    unsigned long code = IrReceiver.decodedIRData.decodedRawData;

    if (isRepeat || code == 0) 
    {
      code = lastPressedCode;
    } else {
      lastPressedCode = code;
    }

    if (code != 0) 
    {
      handleCommand(code);
    }

    IrReceiver.resume();
  }

  if (carMoving && (millis() - lastIRTime > IR_TIMEOUT_MS)) 
  {
    stopCar();
    Serial.println("Stop (released)");
  }

  if (okHeld && (millis() - lastIRTime > IR_TIMEOUT_MS)) 
  {
    okHeld = false;
  }

  if (okHeld && (millis() - lastFlapTime > FLAP_INTERVAL_MS)) 
  {
    flapWings();
    lastFlapTime = millis();
  }
}

void flapWings() 
{
  wingsUp = !wingsUp;
  int angle = wingsUp ? WING_UP_ANGLE : WING_DOWN_ANGLE;
  wingLeft.write(angle);
  wingRight.write(180 - angle); 
}

void handleCommand(unsigned long code) 
{
  switch (code) 
  {
    case aRECV_upper:
      Serial.println("Forward");
      forward();
      break;

    case aRECV_lower:
      Serial.println("Backward");
      backward();
      break;

    case aRECV_Left:
      Serial.println("Turn Left");
      turnLeft();
      break;

    case aRECV_right:
      Serial.println("Turn Right");
      turnRight();
      break;

    case aRECV_ok:
      if (!okHeld) 
      {
        Serial.println("OK - Stop + Flap");
        stopCar();
        okHeld = true;
        flapWings();         
        lastFlapTime = millis();
      }
      break;

    default:
      Serial.print("Unmapped IR code: 0x");
      Serial.println(code, HEX);
      break;
  }
}

void forward() 
{
  digitalWrite(STBY, HIGH);
  digitalWrite(AIN1, HIGH);
  digitalWrite(BIN1, HIGH);
  analogWrite(PWMA, carSpeed);
  analogWrite(PWMB, carSpeed);
  carMoving = true;
}

void backward() {
  digitalWrite(STBY, HIGH);
  digitalWrite(AIN1, LOW);
  digitalWrite(BIN1, LOW);
  analogWrite(PWMA, carSpeed);
  analogWrite(PWMB, carSpeed);
  carMoving = true;
}

void turnLeft() 
{
  digitalWrite(STBY, HIGH);
  digitalWrite(AIN1, HIGH);
  digitalWrite(BIN1, LOW);
  analogWrite(PWMA, carSpeed);
  analogWrite(PWMB, carSpeed);
  carMoving = true;
}

void turnRight() 
{
  digitalWrite(STBY, HIGH);
  digitalWrite(AIN1, LOW);
  digitalWrite(BIN1, HIGH);
  analogWrite(PWMA, carSpeed);
  analogWrite(PWMB, carSpeed);
  carMoving = true;
}

void stopCar() 
{
  analogWrite(PWMA, 0);
  analogWrite(PWMB, 0);
  digitalWrite(STBY, LOW);
  carMoving = false;
}
