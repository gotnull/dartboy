#include <gb/gb.h>
#include <gb/drawing.h>
#include <stdint.h>

// Define the grid size and point structure
#define GRID_SIZE (4 * 4 * 4)
#define POINTS_PER_AXIS 4
#define FIXED_SHIFT 8                 // Using 8-bit fixed-point numbers
#define FIXED(x) ((x) << FIXED_SHIFT) // Convert to fixed-point

// Rotation speed
#define ROTATE_SPEED 2

typedef struct
{
  int16_t x, y, z;           // Position in fixed-point (x, y, z)
  int8_t screen_x, screen_y; // Screen coordinates
  uint8_t col;               // Color of the point (for later)
} Point;

Point points[GRID_SIZE];

// Fixed-point sine and cosine tables
const int16_t sin_table[64] = {
    0, 25, 50, 74, 98, 121, 142, 162,
    181, 199, 215, 229, 242, 253, 261, 268,
    273, 275, 276, 275, 273, 268, 261, 253,
    242, 229, 215, 199, 181, 162, 142, 121,
    98, 74, 50, 25, 0, -25, -50, -74,
    -98, -121, -142, -162, -181, -199, -215, -229,
    -242, -253, -261, -268, -273, -275, -276, -275,
    -273, -268, -261, -253, -242, -229, -215, -199};

const int16_t cos_table[64] = {
    256, 255, 255, 254, 252, 250, 247, 243,
    239, 234, 229, 223, 216, 208, 200, 192,
    183, 174, 164, 153, 142, 131, 119, 107,
    95, 82, 70, 57, 44, 31, 18, 6,
    0, -6, -18, -31, -44, -57, -70, -82,
    -95, -107, -119, -131, -142, -153, -164, -174,
    -183, -192, -200, -208, -216, -223, -229, -234,
    -239, -243, -247, -250, -252, -254, -255, -255};

uint8_t angle = 0;

void rotatePoint(Point *p, uint8_t angle)
{
  // Rotation in X-Z plane
  int16_t cos_a = cos_table[angle];
  int16_t sin_a = sin_table[angle];

  int16_t x = p->x;
  int16_t z = p->z;

  p->x = (x * cos_a - z * sin_a) >> FIXED_SHIFT;
  p->z = (x * sin_a + z * cos_a) >> FIXED_SHIFT;
}

void initializePoints()
{
  int idx = 0;
  int16_t step_size = FIXED(2) / (POINTS_PER_AXIS - 1);

  for (int i = 0; i < POINTS_PER_AXIS; i++)
  {
    for (int j = 0; i < POINTS_PER_AXIS; i++)
    {
      for (int k = 0; k < POINTS_PER_AXIS; k++)
      {
        if (idx < GRID_SIZE)
        {
          points[idx].x = FIXED(-1) + i * step_size;
          points[idx].y = FIXED(-1) + j * step_size;
          points[idx].z = FIXED(-1) + k * step_size;
          points[idx].col = 1 + (i + j + k) % 4; // Just for demo
          idx++;
        }
      }
    }
  }
}

void projectToScreen(Point *p)
{
  // Project 3D points to 2D screen space (simple perspective projection)
  if (p->z < FIXED(1))
    p->z = FIXED(1); // Prevent divide by zero

  p->screen_x = (p->x * 64) / p->z + 80;
  p->screen_y = (p->y * 64) / p->z + 72;
}

void drawPoint(Point *p)
{
  plot_point(p->screen_x, p->screen_y);
}

void update()
{
  for (int i = 0; i < GRID_SIZE; i++)
  {
    rotatePoint(&points[i], angle);
    projectToScreen(&points[i]);
  }

  // Increment the angle for the next frame
  angle = (angle + ROTATE_SPEED) % 64;
}

void render()
{
  // Clear the screen
  wait_vbl_done();
  color(RED, BLACK, SOLID);
  cls();

  // Draw each point
  for (int i = 0; i < GRID_SIZE; i++)
  {
    drawPoint(&points[i]);
  }
}

void main()
{
  initializePoints();

  while (1)
  {
    update();
    render();
  }
}
