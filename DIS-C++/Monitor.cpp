// Monitor.cpp
#include "Monitor.hpp"

void Monitor::MonitorCPU()
{
    while (true)
    {
        double cpuUsage = GetCPULoad();
        std::cout << "CPU Usage: " << cpuUsage << "%" << std::endl;

        MEMORYSTATUSEX ramUsage = GetRAMUsage();
        std::cout << "RAM Used: " << (ramUsage.ullTotalPhys - ramUsage.ullAvailPhys) / (1024 * 1024) << " MB"
                  << std::endl;

        std::chrono::seconds(10);
    }
}

double Monitor::GetCPULoad()
{
    PDH_HQUERY query;
    PDH_HCOUNTER counter;
    PDH_FMT_COUNTERVALUE value;

    PdhOpenQuery(nullptr, 0, &query);
    // PdhAddCounterA(query, L"\\Processor(_Total)\\% Processor Time", 0, &counter);
    PdhCollectQueryData(query);
    PdhGetFormattedCounterValue(counter, PDH_FMT_DOUBLE, NULL, &value);

    PdhCloseQuery(query);

    return value.doubleValue;
}

MEMORYSTATUSEX Monitor::GetRAMUsage()
{
    MEMORYSTATUSEX memInfo;
    memInfo.dwLength = sizeof(memInfo);
    GlobalMemoryStatusEx(&memInfo);
    return memInfo;
}
