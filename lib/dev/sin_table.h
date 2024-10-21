#include <stdint.h>

// sin_table.h
#ifndef SIN_TABLE_H
#define SIN_TABLE_H

const int sin_table[64] = {
    0, 41, 81, 120, 158, 193, 225, 254, 279, 300, 317, 329, 336, 338, 335, 326,
    311, 291, 266, 236, 201, 162, 120, 75, 28, -20, -68, -116, -162, -206, -247, -285,
    -319, -348, -372, -391, -405, -413, -416, -412, -402, -386, -364, -336, -303, -264, -220, -171,
    -118, -62, -3, 56, 114, 171, 225, 275, 322, 364, 402, 435, 463, 485, 502, 512};

#endif // SIN_TABLE_H
