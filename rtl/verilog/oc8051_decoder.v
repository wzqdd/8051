//////////////////////////////////////////////////////////////////////
////                                                              ////
////  8051 core decoder                                           ////
////                                                              ////
////  This file is part of the 8051 cores project                 ////
////  http://www.opencores.org/cores/8051/                        ////
////                                                              ////
////  Description                                                 ////
////   Main 8051 core module. decodes instruction and creates     ////
////   control sigals.                                            ////
////                                                              ////
////  To Do:                                                      ////
////   optimize state machine, especially IDS ASS and AS3         ////
////                                                              ////
////  Author(s):                                                  ////
////      - Simon Teran, simont@opencores.org                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2000 Authors and OPENCORES.ORG                 ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
//
// CVS Revision History
//
// $Log: not supported by cvs2svn $
// Revision 1.13  2002/10/23 16:53:39  simont
// fix bugs in instruction interface
//
// Revision 1.12  2002/10/17 18:50:00  simont
// cahnge interface to instruction rom
//
// Revision 1.11  2002/09/30 17:33:59  simont
// prepared header
//
//

// synopsys translate_off
`include "oc8051_timescale.v"
// synopsys translate_on

`include "oc8051_defines.v"


module oc8051_decoder (clk, rst, op_in, op1_c,
  ram_rd_sel, ram_wr_sel, bit_addr, wr, wr_sfr,
  src_sel1, src_sel2, src_sel3,
  alu_op, psw_set, eq, cy_sel, comp_sel,
  pc_wr, pc_sel, rd, rmw, istb, mem_act, mem_wait);

//
// clk          (in)  clock
// rst          (in)  reset
// op_in        (in)  operation code [oc8051_op_select.op1]
// eq           (in)  compare result [oc8051_comp.eq]
// ram_rd_sel   (out) select, whitch address will be send to ram for read [oc8051_ram_rd_sel.sel, oc8051_sp.ram_rd_sel]
// ram_wr_sel   (out) select, whitch address will be send to ram for write [oc8051_ram_wr_sel.sel -r, oc8051_sp.ram_wr_sel -r]
// wr           (out) write - if 1 then we will write to ram [oc8051_ram_top.wr -r, oc8051_acc.wr -r, oc8051_b_register.wr -r, oc8051_sp.wr-r, oc8051_dptr.wr -r, oc8051_psw.wr -r, oc8051_indi_addr.wr -r, oc8051_ports.wr -r]
// src_sel1     (out) select alu source 1 [oc8051_alu_src1_sel.sel -r]
// src_sel2     (out) select alu source 2 [oc8051_alu_src2_sel.sel -r]
// src_sel3     (out) select alu source 3 [oc8051_alu_src3_sel.sel -r]
// alu_op       (out) alu operation [oc8051_alu.op_code -r]
// psw_set      (out) will we remember cy, ac, ov from alu [oc8051_psw.set -r]
// cy_sel       (out) carry in alu select [oc8051_cy_select.cy_sel -r]
// comp_sel     (out) compare source select [oc8051_comp.sel]
// bit_addr     (out) if instruction is bit addresable [oc8051_ram_top.bit_addr -r, oc8051_acc.wr_bit -r, oc8051_b_register.wr_bit-r, oc8051_sp.wr_bit -r, oc8051_dptr.wr_bit -r, oc8051_psw.wr_bit -r, oc8051_indi_addr.wr_bit -r, oc8051_ports.wr_bit -r]
// pc_wr        (out) pc write [oc8051_pc.wr]
// pc_sel       (out) pc select [oc8051_pc.pc_wr_sel]
// rd           (out) read from rom [oc8051_pc.rd, oc8051_op_select.rd]
// reti         (out) return from interrupt [pin]
// rmw          (out) read modify write feature [oc8051_ports.rmw]
// pc_wait      (out)
//

input clk, rst, eq, mem_wait;
input [7:0] op_in;

output wr, bit_addr, pc_wr, rmw, istb, src_sel3;
output [1:0] psw_set, cy_sel, comp_sel;
output [2:0] mem_act, src_sel1, src_sel2, ram_rd_sel, ram_wr_sel, pc_sel, wr_sfr, op1_c;
output [3:0] alu_op;
output rd;

reg rmw;
reg src_sel3, wr,  bit_addr, pc_wr;
reg [1:0] comp_sel, psw_set, cy_sel;
reg [3:0] alu_op;
reg [2:0] src_sel2, mem_act, src_sel1, ram_wr_sel, ram_rd_sel, pc_sel, wr_sfr;

//
// state        if 2'b00 then normal execution, sle instructin that need more than one clock
// op           instruction buffer
reg [1:0] state;
reg [7:0] op;
wire [7:0] op_cur;

reg stb_i;

assign rd = !state[0] && !state[1];// && !stb_o;

assign istb = (!state[1]) && stb_i;



assign op_cur = (state[0] || state[1] || mem_wait) ? op : op_in;
assign op1_c = op_cur[2:0];


//
// main block
// unregisterd outputs
always @(op_cur or eq or state or mem_wait)
begin
    case (state)
      2'b01: begin
    casex (op_cur)
      `OC8051_MOVC_DP :begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOVC_PC :begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ACALL :begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_AJMP : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_LCALL :begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_DIV : begin
          ram_rd_sel = `OC8051_RRS_B;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MUL : begin
          ram_rd_sel = `OC8051_RRS_B;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      default begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
      end
    endcase
    end
    2'b10:
    casex (op_cur)
      `OC8051_RET : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_Y;
          pc_sel = `OC8051_PIS_AL;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_RETI : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_Y;
          pc_sel = `OC8051_PIS_AL;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CJNE_R : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = !eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_DES;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CJNE_I : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = !eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_DES;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CJNE_D : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = !eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_DES;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CJNE_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = !eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_DES;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_DJNZ_R : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = !eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_DES;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_DJNZ_D : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = !eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_DES;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_JB : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_BIT;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_JBC : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_BIT;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b1;
        end
      `OC8051_JC : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_CY;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_JMP_D : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_Y;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_JNB : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = !eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_BIT;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b1;
        end
      `OC8051_JNC : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = !eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_CY;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_JNZ : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = !eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_AZ;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_JZ : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = eq;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_AZ;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_SJMP : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_Y;
          pc_sel = `OC8051_PIS_ALU;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_DIV : begin
          ram_rd_sel = `OC8051_RRS_B;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MUL : begin
          ram_rd_sel = `OC8051_RRS_B;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      default begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
      end
    endcase

    2'b11:
    casex (op_cur)
      `OC8051_CJNE_R : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CJNE_I : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CJNE_D : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CJNE_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_DJNZ_R : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_DJNZ_D : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_RET : begin
          ram_rd_sel = `OC8051_RRS_SP;
          pc_wr = `OC8051_PCW_Y;
          pc_sel = `OC8051_PIS_AH;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_RETI : begin
          ram_rd_sel = `OC8051_RRS_SP;
          pc_wr = `OC8051_PCW_Y;
          pc_sel = `OC8051_PIS_AH;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_DIV : begin
          ram_rd_sel = `OC8051_RRS_B;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MUL : begin
          ram_rd_sel = `OC8051_RRS_B;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
     default begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
      end
    endcase
    default: begin
    casex (op_cur)
      `OC8051_ACALL :begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_Y;
          pc_sel = `OC8051_PIS_I11;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_AJMP : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_Y;
          pc_sel = `OC8051_PIS_I11;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_ADD_R : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ADDC_R : begin
	  ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ANL_R : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CJNE_R : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_DEC_R : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_DJNZ_R : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_INC_R : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_R : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_AR : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_DR : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_CR : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_RD : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ORL_R : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_SUBB_R : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_XCH_R : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_XRL_R : begin
          ram_rd_sel = `OC8051_RRS_RN;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end

//op_code [7:1]
      `OC8051_ADD_I : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ADDC_I : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ANL_I : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CJNE_I : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_DEC_I : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_INC_I : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_I : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_ID : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_AI : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_DI : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_CI : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOVX_IA : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_MOVX_AI :begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_ORL_I : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_SUBB_I : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_XCH_I : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_XCHD :begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_XRL_I : begin
          ram_rd_sel = `OC8051_RRS_I;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end

//op_code [7:0]
      `OC8051_ADD_D : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ADD_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ADDC_D : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ADDC_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ANL_D : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ANL_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ANL_DD : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ANL_DC : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ANL_B : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b1;
        end
      `OC8051_ANL_NB : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b1;
        end
      `OC8051_CJNE_D : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_CJNE_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_CLR_A : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CLR_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CLR_B : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b1;
        end
      `OC8051_CPL_A : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CPL_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_CPL_B : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b1;
        end
      `OC8051_DA : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_DEC_A : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_DEC_D : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_DIV : begin
          ram_rd_sel = `OC8051_RRS_B;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_DJNZ_D : begin
	  ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_INC_A : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_INC_D : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_INC_DP : begin
	  ram_rd_sel = `OC8051_RRS_DPTR;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_JB : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_BIT;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b1;
        end
      `OC8051_JBC :begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_BIT;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b0;
          bit_addr = 1'b1;
        end
      `OC8051_JC : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_CY;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_JMP_D : begin
          ram_rd_sel = `OC8051_RRS_DPTR;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_JNB : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_BIT;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b1;
        end
      `OC8051_JNC : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_CY;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_JNZ :begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_AZ;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_JZ : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_AZ;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_LCALL :begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_Y;
          pc_sel = `OC8051_PIS_I16;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_LJMP : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_Y;
          pc_sel = `OC8051_PIS_I16;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_D : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end

      `OC8051_MOV_DA : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_DD : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_CD : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOV_BC : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b1;
        end
      `OC8051_MOV_CB : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b1;
        end
      `OC8051_MOV_DP : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_MOVC_DP :begin
          ram_rd_sel = `OC8051_RRS_DPTR;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_MOVC_PC : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_MOVX_PA : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_MOVX_AP : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_MUL : begin
          ram_rd_sel = `OC8051_RRS_B;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_ORL_D : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ORL_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ORL_AD : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ORL_CD : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_ORL_B : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b1;
        end
      `OC8051_ORL_NB : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b1;
        end
      `OC8051_POP : begin
          ram_rd_sel = `OC8051_RRS_SP;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_PUSH : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_RET : begin
          ram_rd_sel = `OC8051_RRS_SP;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_RETI : begin
          ram_rd_sel = `OC8051_RRS_SP;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_RL : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_RLC : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_RR : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_RRC : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_SETB_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_SETB_B : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b1;
        end
      `OC8051_SJMP : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b0;
          bit_addr = 1'b0;
        end
      `OC8051_SUBB_D : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_SUBB_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_SWAP : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_XCH_D : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_XRL_D : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_XRL_C : begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_XRL_AD : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      `OC8051_XRL_CD : begin
          ram_rd_sel = `OC8051_RRS_D;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_Y;
          stb_i = 1'b1;
          bit_addr = 1'b0;
        end
      default: begin
          ram_rd_sel = `OC8051_RRS_DC;
          pc_wr = `OC8051_PCW_N;
          pc_sel = `OC8051_PIS_DC;
          comp_sel =  `OC8051_CSS_DC;
          rmw = `OC8051_RMW_N;
          stb_i = 1'b1;
          bit_addr = 1'b0;
       end
    endcase
    end
    endcase
end










//
//
// registerd outputs

always @(posedge clk or posedge rst)
begin
  if (rst) begin
    ram_wr_sel <= #1 `OC8051_RWS_DC;
    src_sel1 <= #1 `OC8051_AS1_DC;
    src_sel2 <= #1 `OC8051_AS2_DC;
    alu_op <= #1 `OC8051_ALU_NOP;
    wr <= #1 1'b0;
    psw_set <= #1 `OC8051_PS_NOT;
    cy_sel <= #1 `OC8051_CY_0;
    src_sel3 <= #1 `OC8051_AS3_DC;
    wr_sfr <= #1 `OC8051_WRS_N;
  end else  begin
    case (state)
      2'b01: begin
    casex (op_cur)
      `OC8051_MOVC_DP :begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP1;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DP;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_MOVC_PC :begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP1;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_MOVX_PA : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP1;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_MOVX_IA : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP1;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ACALL :begin
          ram_wr_sel <= #1 `OC8051_RWS_SP;
          src_sel1 <= #1 `OC8051_AS1_PCH;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_AJMP : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_LCALL :begin
          ram_wr_sel <= #1 `OC8051_RWS_SP;
          src_sel1 <= #1 `OC8051_AS1_PCH;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DIV : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_DIV;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_OV;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_BA;
        end
      `OC8051_MUL : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_MUL;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_OV;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_BA;
        end
      default begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
      end
    endcase
    end
    2'b10:
    casex (op_cur)
      `OC8051_CJNE_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CJNE_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CJNE_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CJNE_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DJNZ_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DJNZ_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JB : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JBC : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JC : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JMP_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JNB : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JNC : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JNZ : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JZ : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_SJMP : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DIV : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_DIV;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_OV;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MUL : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_MUL;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_OV;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      default begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
      end
    endcase

    2'b11:
    casex (op_cur)
      `OC8051_CJNE_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CJNE_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CJNE_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CJNE_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DJNZ_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DJNZ_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_RET : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_RETI : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DIV : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_DIV;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_OV;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MUL : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_MUL;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_OV;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
     default begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
      end
    endcase
    default: begin
    casex (op_cur)
      `OC8051_ACALL :begin
          ram_wr_sel <= #1 `OC8051_RWS_SP;
          src_sel1 <= #1 `OC8051_AS1_PCL;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_AJMP : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_ADD_R : begin
	  ram_wr_sel <= #1 `OC8051_RWS_DC;
	  src_sel1 <= #1 `OC8051_AS1_ACC;
	  src_sel2 <= #1 `OC8051_AS2_RAM;
	  alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
	  psw_set <= #1 `OC8051_PS_AC;
	  cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ADDC_R : begin
	  ram_wr_sel <= #1 `OC8051_RWS_DC;
	  src_sel1 <= #1 `OC8051_AS1_ACC;
	  src_sel2 <= #1 `OC8051_AS2_RAM;
	  alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
	  psw_set <= #1 `OC8051_PS_AC;
	  cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ANL_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_AND;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_CJNE_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_OP2;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DEC_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_RN;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ZERO;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DJNZ_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_RN;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ZERO;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_INC_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_RN;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ZERO;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_MOV_AR : begin
          ram_wr_sel <= #1 `OC8051_RWS_RN;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_DR : begin
          ram_wr_sel <= #1 `OC8051_RWS_RN;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_CR : begin
          ram_wr_sel <= #1 `OC8051_RWS_RN;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_RD : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_ORL_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_OR;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_SUBB_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_AC;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_XCH_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_RN;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_XCH;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC2;
        end
      `OC8051_XRL_R : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_XOR;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end

//op_code [7:1]
      `OC8051_ADD_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_AC;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ADDC_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_AC;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ANL_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_AND;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_CJNE_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_OP2;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DEC_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_I;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ZERO;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_INC_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_I;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ZERO;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_MOV_ID : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_AI : begin
          ram_wr_sel <= #1 `OC8051_RWS_I;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_DI : begin
          ram_wr_sel <= #1 `OC8051_RWS_I;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_CI : begin
          ram_wr_sel <= #1 `OC8051_RWS_I;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOVX_IA : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOVX_AI :begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_ORL_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_OR;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_SUBB_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_AC;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_XCH_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_I;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_XCH;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC2;
        end
      `OC8051_XCHD :begin
          ram_wr_sel <= #1 `OC8051_RWS_I;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_XCH;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC2;
        end
      `OC8051_XRL_I : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_XOR;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end

//op_code [7:0]
      `OC8051_ADD_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_AC;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ADD_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_AC;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ADDC_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_AC;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ADDC_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_AC;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ANL_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_AND;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ANL_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_AND;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ANL_DD : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_AND;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_ANL_DC : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_AND;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_ANL_B : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_AND;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_ANL_NB : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_RR;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CJNE_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CJNE_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_OP2;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CLR_A : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_CLR_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CLR_B : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CPL_A : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOT;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_CPL_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOT;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_CPL_B : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOT;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_RAM;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DA : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_DA;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_DEC_A : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_ZERO;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_DEC_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ZERO;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DIV : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_DIV;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_OV;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_DJNZ_D : begin
	  ram_wr_sel <= #1 `OC8051_RWS_D;
	  src_sel1 <= #1 `OC8051_AS1_RAM;
	  src_sel2 <= #1 `OC8051_AS2_ZERO;
	  alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b1;
	  psw_set <= #1 `OC8051_PS_NOT;
	  cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_INC_A : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_ZERO;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_INC_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ZERO;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_INC_DP : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ZERO;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DP;
          wr_sfr <= #1 `OC8051_WRS_DPTR;
        end
      `OC8051_JB : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JBC :begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JC : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JMP_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DP;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JNB : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JNC : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JNZ :begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_JZ : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_LCALL :begin
          ram_wr_sel <= #1 `OC8051_RWS_SP;
          src_sel1 <= #1 `OC8051_AS1_PCL;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_LJMP : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_MOV_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_MOV_DA : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_DD : begin
          ram_wr_sel <= #1 `OC8051_RWS_D3;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_CD : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_BC : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_RAM;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_CB : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOV_DP : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_OP2;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_DPTR;
        end
      `OC8051_MOVC_DP :begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DP;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOVC_PC : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_PCL;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_ADD;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOVX_PA : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MOVX_AP : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_MUL : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_MUL;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_OV;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_ORL_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_OR;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ORL_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_OR;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_ORL_AD : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_OR;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_ORL_CD : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_OR;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_ORL_B : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_OR;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_ORL_NB : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_RL;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_POP : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_PUSH : begin
          ram_wr_sel <= #1 `OC8051_RWS_SP;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_RET : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_RETI : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_RL : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_RL;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_RLC : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_RLC;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_RR : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_RR;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_RRC : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_RRC;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_SETB_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_CY;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_SETB_B : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_SJMP : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_PCL;
          alu_op <= #1 `OC8051_ALU_PCS;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_PC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_SUBB_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_AC;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_SUBB_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_OP2;
          alu_op <= #1 `OC8051_ALU_SUB;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_AC;
          cy_sel <= #1 `OC8051_CY_PSW;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_SWAP : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_ACC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_RLC;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC2;
        end
      `OC8051_XCH_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_XCH;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_1;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC2;
        end
      `OC8051_XRL_D : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_XOR;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_XRL_C : begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_OP2;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_XOR;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_ACC1;
        end
      `OC8051_XRL_AD : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_RAM;
          src_sel2 <= #1 `OC8051_AS2_ACC;
          alu_op <= #1 `OC8051_ALU_XOR;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      `OC8051_XRL_CD : begin
          ram_wr_sel <= #1 `OC8051_RWS_D;
          src_sel1 <= #1 `OC8051_AS1_OP3;
          src_sel2 <= #1 `OC8051_AS2_RAM;
          alu_op <= #1 `OC8051_ALU_XOR;
          wr <= #1 1'b1;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
        end
      default: begin
          ram_wr_sel <= #1 `OC8051_RWS_DC;
          src_sel1 <= #1 `OC8051_AS1_DC;
          src_sel2 <= #1 `OC8051_AS2_DC;
          alu_op <= #1 `OC8051_ALU_NOP;
          wr <= #1 1'b0;
          psw_set <= #1 `OC8051_PS_NOT;
          cy_sel <= #1 `OC8051_CY_0;
          src_sel3 <= #1 `OC8051_AS3_DC;
          wr_sfr <= #1 `OC8051_WRS_N;
       end
    endcase
    end
    endcase
  end
end


//
// remember current instruction
always @(posedge clk or posedge rst)
  if (rst) op <= #1 2'b00;
  else if (state==2'b00) op <= #1 op_in;

//
// in case of instructions that needs more than one clock set state
always @(posedge clk or posedge rst)
begin
  if (rst)
    state <= #1 2'b01;
  else if  (!mem_wait) begin
    case (state)
      2'b10: state <= #1 2'b01;
      2'b11: state <= #1 2'b10;
      2'b00:
          casex (op_in)
            `OC8051_ACALL :state <= #1 2'b01;
            `OC8051_AJMP : state <= #1 2'b01;
            `OC8051_CJNE_R :state <= #1 2'b11;
            `OC8051_CJNE_I :state <= #1 2'b11;
            `OC8051_CJNE_D : state <= #1 2'b11;
            `OC8051_CJNE_C : state <= #1 2'b11;
            `OC8051_LJMP : state <= #1 2'b01;
            `OC8051_DJNZ_R :state <= #1 2'b11;
            `OC8051_DJNZ_D :state <= #1 2'b11;
            `OC8051_LCALL :state <= #1 2'b01;
            `OC8051_MOVC_DP :state <= #1 2'b11;
            `OC8051_MOVC_PC :state <= #1 2'b11;
            `OC8051_MOVX_IA :state <= #1 2'b10;
            `OC8051_MOVX_AI :state <= #1 2'b10;
            `OC8051_MOVX_PA :state <= #1 2'b10;
            `OC8051_MOVX_AP :state <= #1 2'b10;
            `OC8051_RET : state <= #1 2'b11;
            `OC8051_RETI : state <= #1 2'b11;
            `OC8051_SJMP : state <= #1 2'b10;
            `OC8051_JB : state <= #1 2'b10;
            `OC8051_JBC : state <= #1 2'b10;
            `OC8051_JC : state <= #1 2'b10;
            `OC8051_JMP_D : state <= #1 2'b10;
            `OC8051_JNC : state <= #1 2'b10;
            `OC8051_JNB : state <= #1 2'b10;
            `OC8051_JNZ : state <= #1 2'b10;
            `OC8051_JZ : state <= #1 2'b10;
            `OC8051_DIV : state <= #1 2'b11;
            `OC8051_MUL : state <= #1 2'b11;
            default: state <= #1 2'b00;
          endcase
      default: state <= #1 2'b00;
    endcase
  end
end


//
//in case of writing to external ram
always @(posedge clk or posedge rst)
begin
  if (rst) begin
    mem_act <= #1 `OC8051_MAS_NO;
  end else if (!rd) begin
    mem_act <= #1 `OC8051_MAS_NO;
  end else
    casex (op_cur)
      `OC8051_MOVX_AI : mem_act <= #1 `OC8051_MAS_RI_W;
      `OC8051_MOVX_AP : mem_act <= #1 `OC8051_MAS_DPTR_W;
      `OC8051_MOVX_IA : mem_act <= #1 `OC8051_MAS_RI_R;
      `OC8051_MOVX_PA : mem_act <= #1 `OC8051_MAS_DPTR_R;
      `OC8051_MOVC_DP : mem_act <= #1 `OC8051_MAS_CODE;
      `OC8051_MOVC_PC : mem_act <= #1 `OC8051_MAS_CODE;
      default : mem_act <= #1 `OC8051_MAS_NO;
    endcase
end

endmodule


