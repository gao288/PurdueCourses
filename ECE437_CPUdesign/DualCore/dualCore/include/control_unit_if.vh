`ifndef CONTROL_UNIT_IF_VH
 `define CONTROL_UNIT_IF_VH
 `include "cpu_types_pkg.vh"
interface control_unit_if;
   import cpu_types_pkg::*;
   
   word_t instr;

   logic [AOP_W-1:0] aluop;
   logic             dREN, dWEN, aluin_sel, halt,
                     rWEN, shamt_sel, jal, bran,datomic;
   logic [1:0]       wdat_sel, extop, pcsrc;
   regbits_t wsel_sel;
   
   modport cuif(
                //from cache
                input instr,
                //to request unit
                output dREN, dWEN,
                //to mux
                pcsrc, wsel_sel, extop, aluin_sel, shamt_sel,
                //to alu
                aluop,
                //to register
                rWEN, bran,
                //to datapath
                halt, jal,datomic);
endinterface
  
`endif