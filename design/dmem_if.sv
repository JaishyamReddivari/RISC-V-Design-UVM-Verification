interface dmem_if #(parameter XLEN = 32)
  (input logic clk);

    logic              valid;
    logic              write;
    logic [3:0]        wstrb;
    logic [XLEN-1:0]   addr;
    logic [XLEN-1:0]   wdata;
    logic [XLEN-1:0]   rdata;
    logic              ready;

    modport master (
        output valid,
        output write,
        output wstrb,
        output addr,
        output wdata,
        input  rdata,
        input  ready
    );

    modport slave (
        input  valid,
        input  write,
        input  wstrb,
        input  addr,
        input  wdata,
        output rdata,
        output ready
    );

endinterface
