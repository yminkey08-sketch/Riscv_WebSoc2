//****************************************Copyright 2013[c]************************//
// ************************Declaration***************************************//
// File name:        clock_frequency_divider	                                       //
// Author:           huaming.huang@link-real.com.cn                                    //
// Date:             2014-12-12 00:00 	                                     //
// Version Number:   1.0                                                     //
// Abstract:    arbitrarily and configurable frequency divide for clock,
//              ref LR_IP design DOC.
//              if need 7/3 divide for ref clock, set div_M=11, div_N=3 and div_Mbits=4, div_Nbits = 2;
//              if just need 2 divide for ref clock, set div_M=2, div_N=1
// Modification history:[including time, version, author and abstract]        //
// 2014-12-12 00:00        version 1.0     xxx                                //
// Abstract: Initial                                                          //
//                                                                            //
// *********************************end************************************** //

module clock_frequency_divider (
    reset_l,
    clk_in,

    div_M,  //div_M >= 2
    div_N,  //div_M/div_N >= 2					 
    clk_out
);
  parameter div_Mbits = 9, div_Nbits = 1;
  input reset_l;
  input clk_in;

  input [div_Mbits-1:0] div_M;
  input [div_Nbits-1:0] div_N;
  output clk_out;

  reg [div_Mbits+1:0] count;
  reg                 clk_out;

  always @(negedge reset_l or posedge clk_in)
    if (reset_l == 1'b0) begin
      count   <= 32'b0;
      clk_out <= 1'b0;
    end else begin
      if (count + 2 * div_N >= div_M) begin
        count   <= count + 2 * div_N - div_M;
        clk_out <= ~clk_out;
      end else begin
        count <= count + 2 * div_N;
      end
    end
endmodule  // clock_frequency_divider

