/* q9's probe header (road map 10 G0). The throwaway export is declared HERE
 * and never in core/include/reelcut_core.h; the two others are the core's
 * own, for the CONTROL build and for freeing. */
#include <stddef.h>
#include <stdint.h>

char *rc_graphic_spike_render(const char *source, int64_t frame, uint32_t width, uint32_t height,
                              const uint8_t *font_bytes, size_t font_len, char **err_out);
char *rc_op_names(void);
void rc_string_free(char *s);
