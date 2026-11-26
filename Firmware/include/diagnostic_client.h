#pragma once

#include <Arduino.h>

void diagnosticClientTask(void *parameter);

int requestLatestFirmwareFromDiagnosticServer(String *responseOut);