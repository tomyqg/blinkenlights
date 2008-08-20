/***************************************************************
 *
 * OpenBeacon.org - OpenBeacon dimmer link layer protocol
 *
 * Copyright 2008 Milosch Meriac <meriac@openbeacon.de>
 *                Daniel Mack <daniel@caiaq.de>
 *
 ***************************************************************

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; version 2.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

*/
#include <FreeRTOS.h>
#include <semphr.h>
#include <task.h>
#include <string.h>
#include <math.h>
#include <board.h>
#include <beacontypes.h>
#include <USB-CDC.h>
#include "led.h"
#include "xxtea.h"
#include "proto.h"
#include "env.h"

#define LINE_HERTZ_LOWPASS_SIZE		50
#define DIMMER_TICKS			10000
#define DIMMER_JITTER_US		150
#define MINIMAL_PULSE_LENGH_US		160
#define PWM_CMR_CLOCK_FREQUENCY		(MCK/8)


#define DIMMER_JITTER_TICKS ((int)((DIMMER_JITTER_US * ((unsigned long long)PWM_CMR_CLOCK_FREQUENCY)) / 1000000))

static unsigned short line_hz_table[LINE_HERTZ_LOWPASS_SIZE];
static int line_hz_pos, line_hz_sum, line_hz, line_hz_enabled;
static int dimmer_step;

int
dimmer_line_hz_enabled (void)
{
  return line_hz_enabled;
}

static inline unsigned int
PtRandom (void)
{
  static unsigned int v1 = 0x52f7d319;
  static unsigned int v2 = 0x6e28014a;

  // MWC generator, period length 1014595583
  return ((v1 = 36969 * (v1 & 0xffff) + (v1 >> 16)) << 16) ^ (v2 =
							      30963 *
							      (v2 & 0xffff) +
							      (v2 >> 16));
}

void __attribute__ ((section (".ramfunc"))) vnRF_PulseIRQ_Handler (void)
{
  static unsigned int timer_prev = 0;
  int pulse_length, rb, period_length;
  int dimmer_percent = DIMMER_TICKS - env.e.gamma_table[dimmer_step];

  if (AT91C_BASE_TC1->TC_SR & AT91C_TC_LDRBS)
    {
      rb = AT91C_BASE_TC1->TC_RB;
      pulse_length = (rb - AT91C_BASE_TC1->TC_RA) & 0xFFFF;

      if (pulse_length >
	  ((MINIMAL_PULSE_LENGH_US * PWM_CMR_CLOCK_FREQUENCY) / 1000000))
	{
	  if (line_hz_enabled)
	    {
	      pulse_length = (line_hz * dimmer_percent) / DIMMER_TICKS;
	      pulse_length +=
		(PtRandom () % (DIMMER_JITTER_TICKS * 2)) -
		DIMMER_JITTER_TICKS;

	      AT91C_BASE_TC2->TC_RA = pulse_length > 0 ? pulse_length : 1;
	      AT91C_BASE_TC2->TC_CCR = AT91C_TC_SWTRG;
	    }

	  period_length = (rb - timer_prev) & 0xFFFF;
	  timer_prev = rb;

	  line_hz_sum += period_length - line_hz_table[line_hz_pos];
	  line_hz = line_hz_sum / LINE_HERTZ_LOWPASS_SIZE;
	  AT91C_BASE_TC2->TC_RC = (line_hz * 82) / 100;

	  line_hz_table[line_hz_pos++] = (unsigned short) period_length;
	  if (line_hz_pos >= LINE_HERTZ_LOWPASS_SIZE)
	    {
	      line_hz_enabled = pdTRUE;
	      line_hz_pos = 0;
	    }
	}
    }

  AT91C_BASE_AIC->AIC_EOICR = 0;
}

void __attribute__ ((naked, section (".ramfunc"))) vnRF_PulseIRQ (void)
{
  portSAVE_CONTEXT ();
  vnRF_PulseIRQ_Handler ();
  portRESTORE_CONTEXT ();
}

void
vUpdateDimmer (int step)
{
  if (step > GAMMA_SIZE || step < 0)
    return;

  dimmer_step = step;
}

int
vGetDimmerStep (void)
{
  return dimmer_step;
}

void
vSetDimmerGamma (int entry, int val)
{
  if (entry >= GAMMA_SIZE)
    return;

  if (val < 0)
    val = 0;
  else if (val >= DIMMER_TICKS)
    val = DIMMER_TICKS;

  env.e.gamma_table[entry] = val;
}

void
vInitDimmer (void)
{
  /* reset Dimmer and gamma correction to default value */
  /* vGammaRecalc (GAMMA_DEFAULT); */

  bzero (&line_hz_table, sizeof (line_hz_table));
  line_hz_pos = line_hz_sum = line_hz = line_hz_enabled = 0;
  dimmer_step = 0;

  /* Enable Peripherals */
  AT91F_PIO_CfgPeriph (AT91C_BASE_PIOA, 0, TRIGGER_PIN | PHASE_PIN);
  AT91F_PIO_CfgInputFilter (AT91C_BASE_PIOA, TRIGGER_PIN | PHASE_PIN);

  /* Configure Timer/Counter 1 */
  AT91F_TC1_CfgPMC ();
  AT91C_BASE_TC1->TC_CCR = AT91C_TC_CLKDIS;
  AT91C_BASE_TC1->TC_IDR = 0xFF;
  AT91C_BASE_TC1->TC_CMR =
    AT91C_TC_CLKS_TIMER_DIV2_CLOCK |
    AT91C_TC_LDRA_RISING | AT91C_TC_LDRB_FALLING;
  AT91C_BASE_TC1->TC_CCR = AT91C_TC_CLKEN;
  AT91F_AIC_ConfigureIt (AT91C_ID_TC1, 7, AT91C_AIC_SRCTYPE_INT_POSITIVE_EDGE,
			 vnRF_PulseIRQ);
  AT91C_BASE_TC1->TC_IER = AT91C_TC_LDRBS;
  AT91F_AIC_EnableIt (AT91C_ID_TC1);

  /* Configure Timer/Counter 2 */
  AT91F_TC2_CfgPMC ();
  AT91C_BASE_TC2->TC_CCR = AT91C_TC_CLKDIS;
  AT91C_BASE_TC2->TC_IDR = 0xFF;
  AT91C_BASE_TC2->TC_CMR =
    AT91C_TC_CLKS_TIMER_DIV2_CLOCK |
    AT91C_TC_CPCSTOP |
    AT91C_TC_WAVE |
    AT91C_TC_WAVESEL_UP_AUTO | AT91C_TC_ACPA_SET | AT91C_TC_ACPC_CLEAR;
  vUpdateDimmer (0);
  AT91C_BASE_TC2->TC_CCR = AT91C_TC_CLKEN;

  AT91C_BASE_TCB->TCB_BCR = AT91C_TCB_SYNC;
  AT91C_BASE_TCB->TCB_BMR =
    AT91C_TCB_TC0XC0S_NONE | AT91C_TCB_TC1XC1S_NONE | AT91C_TCB_TC2XC2S_NONE;
}