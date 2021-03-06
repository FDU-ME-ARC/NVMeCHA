`timescale 1ns / 1ps
/**
* NVMeCHA: NVMe Controller featuring Hardware Acceleration
* Copyright (C) 2021 State Key Laboratory of ASIC and System, Fudan University
* Contributed by Yunhui Qiu
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

//////////////////////////////////////////////////////////////////////////////////
// Company:  State Key Laboratory of ASIC and System, Fudan University
// Engineer: Yunhui Qiu
// 
// Create Date: 03/26/2020 04:53:40 PM
// Design Name: 
// Module Name: nvme_admin_data_fetch
// Project Name: SSD Controller
// Target Devices: 
// Tool Versions: 
// Description: fetch data from host to card for Admin Commands
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`include "nvme_param.vh"

module nvme_admin_data_fetch#(
    parameter DATA_WIDTH = 256
)(
    input                        clk,
    input                        rst_n,
    
    // DMA descriptor info generated by PS
    input      [31 : 0]          ps_dsc_ctl, // [0] load, trace rising edge
    input      [31 : 0]          ps_dsc_len,
    input      [63 : 0]          ps_dsc_addr,
    
    output reg                   dma_trans_done,

    // BRAM Ports, Read Only
    input                        bp_clk,
    input                        bp_rst,
    input                        bp_en,
    input      [ 15:0]           bp_we,
    input      [ 12:0]           bp_addr,
    input      [127:0]           bp_wrdata,
    output     [127:0]           bp_rddata, 
    
    // H2C DMA descriptor
    input                        h2c_dsc_byp_ready,   
    output reg                   h2c_dsc_byp_load, 
    output reg [63 : 0]          h2c_dsc_byp_src_addr,   
    output reg [63 : 0]          h2c_dsc_byp_dst_addr,   
    output reg [27 : 0]          h2c_dsc_byp_len,   
    output reg [15 : 0]          h2c_dsc_byp_ctl,
    
    // AXI ST interface to fetch programming data
    output reg                   axis_h2c_tready,
    input                        axis_h2c_tvalid,
    input  [DATA_WIDTH-1:0]      axis_h2c_tdata,
    input  [DATA_WIDTH/8-1:0]    axis_h2c_tkeep,
    input                        axis_h2c_tlast  
);


localparam
    IDLE    = 3'b001,
    LOAD    = 3'b010,
    DATA    = 3'b100;

reg  [2:0] state;

wire ps_dsc_load_w;
reg  ps_dsc_load_r;

wire         bram_wen;
reg  [  6:0] bram_waddr;
wire [255:0] bram_wdata;

admin_data_bram admin_h2c_data_bram(            
  .clka  (clk          ),   // input wire clka              
  .ena   (bram_wen     ),   // input wire ena              
  .wea   (32'hffff     ),   // input wire [31 : 0] wea     
  .addra (bram_waddr   ),   // input wire [6 : 0] addra    
  .dina  (bram_wdata   ),   // input wire [255 : 0] dina   
  .douta (             ),   // output wire [255 : 0] douta 
  .clkb  (clk          ),   // input wire clkb             
  .enb   (bp_en        ),   // input wire enb              
  .web   (bp_we        ),   // input wire [15 : 0] web     
  .addrb (bp_addr[11:4]),   // input wire [7 : 0] addrb    
  .dinb  (256'h0       ),   // input wire [127 : 0] dinb   
  .doutb (bp_rddata    )    // output wire [127 : 0] doutb  
);


assign ps_dsc_load_w = ps_dsc_ctl[0];

always@(posedge clk or negedge rst_n)
if(~rst_n) begin
    ps_dsc_load_r <= 1'b0;
end else begin
    ps_dsc_load_r <= ps_dsc_load_w;
end  


always@(posedge clk or negedge rst_n)
if(~rst_n) begin
    state <= IDLE;
end else begin
    case(state)
        IDLE: begin
            if(ps_dsc_load_w & (~ps_dsc_load_r)) begin
                state <= LOAD;
            end else begin
                state <= IDLE;
            end
        end
        LOAD: begin
            if(h2c_dsc_byp_ready) begin
                state <= DATA;
            end else begin
                state <= LOAD;
            end
        end
        DATA: begin
            if(axis_h2c_tready & axis_h2c_tvalid & axis_h2c_tlast) begin
                state <= IDLE;
            end
        end
    endcase
end


// Submit DMA descriptor to transfer data
always@(posedge clk or negedge rst_n)
if(~rst_n) begin
    h2c_dsc_byp_load     <= 1'h0;
    h2c_dsc_byp_len      <= 28'h0;
    h2c_dsc_byp_src_addr <= 64'h0;
    h2c_dsc_byp_dst_addr <= 64'h0;
    h2c_dsc_byp_ctl      <= 16'h0;
end else if((state == LOAD) & h2c_dsc_byp_ready) begin
    h2c_dsc_byp_load     <= 1'h1;
    h2c_dsc_byp_len      <= ps_dsc_len[27:0];
    h2c_dsc_byp_src_addr <= ps_dsc_addr;
    h2c_dsc_byp_dst_addr <= 64'h0;
    h2c_dsc_byp_ctl      <= 16'h10;
end else begin
    h2c_dsc_byp_load     <= 1'h0;
//    h2c_dsc_byp_len      <= 28'h0;
//    h2c_dsc_byp_src_addr <= 64'h0;
//    h2c_dsc_byp_dst_addr <= 64'h0;
//    h2c_dsc_byp_ctl      <= 16'h0;
end 



always@(posedge clk or negedge rst_n)
if(~rst_n) begin
    axis_h2c_tready <= 1'b0;
end else if(state == DATA) begin
    axis_h2c_tready <= 1'b1;
end else begin
    axis_h2c_tready <= 1'b0;
end


assign bram_wen = axis_h2c_tready & axis_h2c_tvalid;
assign bram_wdata = axis_h2c_tdata;


always@(posedge clk or negedge rst_n)
if(~rst_n) begin
    bram_waddr <= 7'h0;
end else if(state == LOAD) begin
    bram_waddr <= 7'h0;
end else if(bram_wen) begin
    bram_waddr <= bram_waddr + 7'h1;
end


always@(posedge clk or negedge rst_n)
if(~rst_n) begin
    dma_trans_done <= 1'h0;
end else if(axis_h2c_tready & axis_h2c_tvalid & axis_h2c_tlast) begin
    dma_trans_done <= 1'h1;
end else if(state == LOAD) begin
    dma_trans_done <= 1'h0;
end





endmodule
