/* ladspa.h  --  Linux Audio Developer's Simple Plugin API, version 1.1
 *
 * Copyright (C) 2000-2002 Richard W.E. Furse, Paul Barton-Davis,
 * Stefan Westerfeld.  This header is in the public domain / LGPL-free
 * to copy; it is vendored here verbatim in substance so that TekVoice
 * builds without the `ladspa` package installed.
 */
#ifndef LADSPA_INCLUDED
#define LADSPA_INCLUDED
#define LADSPA_VERSION "1.1"
#define LADSPA_VERSION_MAJOR 1
#define LADSPA_VERSION_MINOR 1
#ifdef __cplusplus
extern "C" {
#endif

typedef float LADSPA_Data;

typedef int LADSPA_Properties;
#define LADSPA_PROPERTY_REALTIME        0x1
#define LADSPA_PROPERTY_INPLACE_BROKEN  0x2
#define LADSPA_PROPERTY_HARD_RT_CAPABLE 0x4
#define LADSPA_IS_REALTIME(x)        ((x) & LADSPA_PROPERTY_REALTIME)
#define LADSPA_IS_INPLACE_BROKEN(x)  ((x) & LADSPA_PROPERTY_INPLACE_BROKEN)
#define LADSPA_IS_HARD_RT_CAPABLE(x) ((x) & LADSPA_PROPERTY_HARD_RT_CAPABLE)

typedef int LADSPA_PortDescriptor;
#define LADSPA_PORT_INPUT   0x1
#define LADSPA_PORT_OUTPUT  0x2
#define LADSPA_PORT_CONTROL 0x4
#define LADSPA_PORT_AUDIO   0x8
#define LADSPA_IS_PORT_INPUT(x)   ((x) & LADSPA_PORT_INPUT)
#define LADSPA_IS_PORT_OUTPUT(x)  ((x) & LADSPA_PORT_OUTPUT)
#define LADSPA_IS_PORT_CONTROL(x) ((x) & LADSPA_PORT_CONTROL)
#define LADSPA_IS_PORT_AUDIO(x)   ((x) & LADSPA_PORT_AUDIO)

typedef int LADSPA_PortRangeHintDescriptor;
#define LADSPA_HINT_BOUNDED_BELOW   0x1
#define LADSPA_HINT_BOUNDED_ABOVE   0x2
#define LADSPA_HINT_TOGGLED         0x4
#define LADSPA_HINT_SAMPLE_RATE     0x8
#define LADSPA_HINT_LOGARITHMIC     0x10
#define LADSPA_HINT_INTEGER         0x20
#define LADSPA_HINT_DEFAULT_MASK    0x3C0
#define LADSPA_HINT_DEFAULT_NONE    0x0
#define LADSPA_HINT_DEFAULT_MINIMUM 0x40
#define LADSPA_HINT_DEFAULT_LOW     0x80
#define LADSPA_HINT_DEFAULT_MIDDLE  0xC0
#define LADSPA_HINT_DEFAULT_HIGH    0x100
#define LADSPA_HINT_DEFAULT_MAXIMUM 0x140
#define LADSPA_HINT_DEFAULT_0       0x200
#define LADSPA_HINT_DEFAULT_1       0x240
#define LADSPA_HINT_DEFAULT_100     0x280
#define LADSPA_HINT_DEFAULT_440     0x2C0
#define LADSPA_IS_HINT_BOUNDED_BELOW(x) ((x) & LADSPA_HINT_BOUNDED_BELOW)
#define LADSPA_IS_HINT_BOUNDED_ABOVE(x) ((x) & LADSPA_HINT_BOUNDED_ABOVE)
#define LADSPA_IS_HINT_TOGGLED(x)       ((x) & LADSPA_HINT_TOGGLED)
#define LADSPA_IS_HINT_SAMPLE_RATE(x)   ((x) & LADSPA_HINT_SAMPLE_RATE)
#define LADSPA_IS_HINT_LOGARITHMIC(x)   ((x) & LADSPA_HINT_LOGARITHMIC)
#define LADSPA_IS_HINT_INTEGER(x)       ((x) & LADSPA_HINT_INTEGER)

typedef struct _LADSPA_PortRangeHint {
  LADSPA_PortRangeHintDescriptor HintDescriptor;
  LADSPA_Data LowerBound;
  LADSPA_Data UpperBound;
} LADSPA_PortRangeHint;

typedef void * LADSPA_Handle;

typedef struct _LADSPA_Descriptor {
  unsigned long UniqueID;
  const char * Label;
  LADSPA_Properties Properties;
  const char * Name;
  const char * Maker;
  const char * Copyright;
  unsigned long PortCount;
  const LADSPA_PortDescriptor * PortDescriptors;
  const char * const * PortNames;
  const LADSPA_PortRangeHint * PortRangeHints;
  void * ImplementationData;
  LADSPA_Handle (*instantiate)(const struct _LADSPA_Descriptor * Descriptor,
                               unsigned long SampleRate);
  void (*connect_port)(LADSPA_Handle Instance, unsigned long Port,
                       LADSPA_Data * DataLocation);
  void (*activate)(LADSPA_Handle Instance);
  void (*run)(LADSPA_Handle Instance, unsigned long SampleCount);
  void (*run_adding)(LADSPA_Handle Instance, unsigned long SampleCount);
  void (*set_run_adding_gain)(LADSPA_Handle Instance, LADSPA_Data Gain);
  void (*deactivate)(LADSPA_Handle Instance);
  void (*cleanup)(LADSPA_Handle Instance);
} LADSPA_Descriptor;

const LADSPA_Descriptor * ladspa_descriptor(unsigned long Index);
typedef const LADSPA_Descriptor *
(*LADSPA_Descriptor_Function)(unsigned long Index);

#ifdef __cplusplus
}
#endif
#endif /* LADSPA_INCLUDED */
