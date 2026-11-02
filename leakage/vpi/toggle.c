/*
 * toggle.c - whole-design toggle-count leakage model for Icarus Verilog
 *
 * System tasks (called from leakage/tb_leak.v):
 *
 *   $tg_init(scope)       collect every reg (vector or scalar) below the
 *                         module instance `scope`, memories excluded; for
 *                         the RTL of this repository, which has no
 *                         combinational `always`, this is every flip-flop
 *                         and every BRAM output latch of the design
 *   $tg_open(path)        open the trace file (one uint16 per sample)
 *   $tg_sync              take the current register state as reference
 *   $tg_sample            append one sample: number of bits that differ
 *                         between the current state and the reference,
 *                         then make the current state the reference
 *   $tg_flush(expected)   write the samples of this execution as one row;
 *                         stops the simulation if the row length differs
 *                         from `expected` (every row must be aligned)
 *   $tg_close
 *
 *   $tg_dump_open(path)   dump mode for the oracle: $tg_dump writes the
 *   $tg_dump              value of every collected reg (int32, sign-
 *                         extended for signed regs) at the current time
 *   $tg_names(path)       write "index width signed fullname" per reg
 *
 * Bits that are x or z count as 0. The sample is the Hamming distance
 * between consecutive register states, summed over the whole design: both
 * share domains and the shared control.
 */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <vpi_user.h>

#define MAXREGS 8192

static vpiHandle regs[MAXREGS];
static int       widths[MAXREGS];
static int       signeds[MAXREGS];
static int       words_of[MAXREGS];
static int       offs[MAXREGS];
static int       nregs = 0, nwords = 0;
static uint32_t *prev = NULL, *cur = NULL;

static FILE     *trace_fp = NULL;
static FILE     *dump_fp  = NULL;
static uint16_t *row = NULL;
static int       row_len = 0, row_cap = 0;

static void collect(vpiHandle mod)
{
    vpiHandle it, h;
    it = vpi_iterate(vpiReg, mod);
    if (it) {
        while ((h = vpi_scan(it)) != NULL) {
            if (nregs >= MAXREGS) {
                vpi_printf("toggle: too many regs\n");
                vpi_control(vpiFinish, 1);
                return;
            }
            regs[nregs]    = h;
            widths[nregs]  = vpi_get(vpiSize, h);
            signeds[nregs] = vpi_get(vpiSigned, h);
            nregs++;
        }
    }
    it = vpi_iterate(vpiModule, mod);
    if (it)
        while ((h = vpi_scan(it)) != NULL) collect(h);
}

static void read_state(uint32_t *dst)
{
    s_vpi_value v;
    v.format = vpiVectorVal;
    for (int i = 0; i < nregs; i++) {
        vpi_get_value(regs[i], &v);
        for (int w = 0; w < words_of[i]; w++)
            dst[offs[i] + w] = v.value.vector[w].aval & ~v.value.vector[w].bval;
        /* mask the unused bits of the top word */
        int r = widths[i] % 32;
        if (r) dst[offs[i] + words_of[i] - 1] &= (1u << r) - 1u;
    }
}

static vpiHandle first_arg(void)
{
    vpiHandle call = vpi_handle(vpiSysTfCall, NULL);
    vpiHandle it = vpi_iterate(vpiArgument, call);
    if (!it) return NULL;
    vpiHandle a = vpi_scan(it);
    vpi_free_object(it);
    return a;
}

static char *arg_string(void)
{
    static char buf[4096];
    vpiHandle a = first_arg();
    s_vpi_value v;
    v.format = vpiStringVal;
    vpi_get_value(a, &v);
    strncpy(buf, v.value.str, sizeof buf - 1);
    buf[sizeof buf - 1] = 0;
    return buf;
}

static int arg_int(void)
{
    vpiHandle a = first_arg();
    s_vpi_value v;
    v.format = vpiIntVal;
    vpi_get_value(a, &v);
    return v.value.integer;
}

static PLI_INT32 tg_init(PLI_BYTE8 *ud)
{
    (void)ud;
    vpiHandle scope = first_arg();
    nregs = 0;
    collect(scope);
    nwords = 0;
    for (int i = 0; i < nregs; i++) {
        words_of[i] = (widths[i] + 31) / 32;
        offs[i] = nwords;
        nwords += words_of[i];
    }
    free(prev); free(cur);
    prev = calloc(nwords, 4);
    cur  = calloc(nwords, 4);
    int bits = 0;
    for (int i = 0; i < nregs; i++) bits += widths[i];
    vpi_printf("toggle: %d regs, %d bits below %s\n", nregs, bits,
               vpi_get_str(vpiFullName, scope));
    return 0;
}

static PLI_INT32 tg_open(PLI_BYTE8 *ud)
{
    (void)ud;
    trace_fp = fopen(arg_string(), "wb");
    if (!trace_fp) { vpi_printf("toggle: cannot open trace file\n"); vpi_control(vpiFinish, 1); }
    return 0;
}

static PLI_INT32 tg_sync(PLI_BYTE8 *ud)
{
    (void)ud;
    read_state(prev);
    row_len = 0;
    return 0;
}

static PLI_INT32 tg_sample(PLI_BYTE8 *ud)
{
    (void)ud;
    read_state(cur);
    int hd = 0;
    for (int w = 0; w < nwords; w++) hd += __builtin_popcount(prev[w] ^ cur[w]);
    uint32_t *t = prev; prev = cur; cur = t;
    if (row_len == row_cap) {
        row_cap = row_cap ? 2 * row_cap : 16384;
        row = realloc(row, row_cap * sizeof *row);
    }
    row[row_len++] = (uint16_t)hd;
    return 0;
}

static PLI_INT32 tg_flush(PLI_BYTE8 *ud)
{
    (void)ud;
    int expected = arg_int();
    if (expected > 0 && row_len != expected) {
        vpi_printf("toggle: row of %d samples, expected %d\n", row_len, expected);
        vpi_control(vpiFinish, 1);
        return 0;
    }
    if (trace_fp) fwrite(row, sizeof *row, row_len, trace_fp);
    row_len = 0;
    return 0;
}

static PLI_INT32 tg_close(PLI_BYTE8 *ud)
{
    (void)ud;
    if (trace_fp) fclose(trace_fp);
    if (dump_fp) fclose(dump_fp);
    trace_fp = dump_fp = NULL;
    return 0;
}

static PLI_INT32 tg_dump_open(PLI_BYTE8 *ud)
{
    (void)ud;
    dump_fp = fopen(arg_string(), "wb");
    if (!dump_fp) { vpi_printf("toggle: cannot open dump file\n"); vpi_control(vpiFinish, 1); }
    return 0;
}

static PLI_INT32 tg_dump(PLI_BYTE8 *ud)
{
    (void)ud;
    static int32_t *vals = NULL;
    static int cap = 0;
    if (cap < nregs) { cap = nregs; vals = realloc(vals, cap * sizeof *vals); }
    read_state(cur);
    for (int i = 0; i < nregs; i++) {
        uint32_t x = cur[offs[i]];           /* regs are at most 32 bits */
        int w = widths[i];
        if (signeds[i] && w < 32 && (x >> (w - 1)) & 1u) x |= ~((1u << w) - 1u);
        vals[i] = (int32_t)x;
    }
    fwrite(vals, sizeof *vals, nregs, dump_fp);
    return 0;
}

static PLI_INT32 tg_names(PLI_BYTE8 *ud)
{
    (void)ud;
    FILE *f = fopen(arg_string(), "w");
    for (int i = 0; i < nregs; i++)
        fprintf(f, "%d %d %d %s\n", i, widths[i], signeds[i],
                vpi_get_str(vpiFullName, regs[i]));
    fclose(f);
    return 0;
}

static void reg_task(const char *name, PLI_INT32 (*fn)(PLI_BYTE8 *))
{
    s_vpi_systf_data d;
    memset(&d, 0, sizeof d);
    d.type = vpiSysTask;
    d.tfname = (PLI_BYTE8 *)name;
    d.calltf = fn;
    vpi_register_systf(&d);
}

static void register_all(void)
{
    reg_task("$tg_init", tg_init);
    reg_task("$tg_open", tg_open);
    reg_task("$tg_sync", tg_sync);
    reg_task("$tg_sample", tg_sample);
    reg_task("$tg_flush", tg_flush);
    reg_task("$tg_close", tg_close);
    reg_task("$tg_dump_open", tg_dump_open);
    reg_task("$tg_dump", tg_dump);
    reg_task("$tg_names", tg_names);
}

void (*vlog_startup_routines[])(void) = { register_all, 0 };
