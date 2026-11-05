// Monitor.hpp
#pragma once

#include "util.hpp"

class Monitor
{
public:
    static void MonitorCPU();
    static double GetCPULoad();
    static MEMORYSTATUSEX GetRAMUsage();
};
