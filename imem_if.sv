// imem_if.sv
interface imem_if #(parameter XLEN = 32);

    logic              req;
    logic [XLEN-1:0]   addr;
    logic [XLEN-1:0]   rdata;
    logic              ready;

    modport master (
        output req,
        output addr,
        input  rdata,
        input  ready
    );

    modport slave (
        input  req,
        input  addr,
        output rdata,
        output ready
    );

endinterface