#include <stdint.h>
const float FasterClamp(const float x, const float min, const float max) {
    float d_a = min-x;
    float d_b = x-max;
    uint32_t Flag_A = (*(uint32_t*)&d_a)>>31;
    uint32_t Flag_B = (*(uint32_t*)&d_b)>>31;
    uint8_t OOR = (Flag_A & Flag_B);
    return (OOR*x) + ((1-Flag_A)*min) + ((1-Flag_B)*max);
}
