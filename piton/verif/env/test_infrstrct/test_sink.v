// Copyright (c) 2015 Princeton University
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of Princeton University nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY PRINCETON UNIVERSITY "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL PRINCETON UNIVERSITY BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

/*
 * Contains a test sink module for checking output vectors from
 * a module or set of modules. Correct output vectors are read from
 * a .vmh file
 */

//`include "test_infrstrct.v"

module test_sink
#(
    parameter VERBOSITY     = 0,        // verbosity of text output
    parameter BIT_WIDTH     = 64,       // data width of output
    //parameter RANDOM_DELAY  = 0,        // random delay between reading output
    parameter ENTRIES       = 1024,     // number of output entries
    parameter LOG2_ENTRIES  = 10        // log base 2 of number of output entries
)
(
    input                   clk,
    input                   rst_n,

    input [BIT_WIDTH-1:0]   bits,
    input                   val,

    output reg              rdy,
    output reg              out_data_popped,
    output reg              done
);

    // This is really a parameter, but VCS doesn't like
    // parameters to be used in left hand sides of always @ *
    // blocks like I want to use it for the test benches.
    // Thus, it is a reg.
    reg [63:0] RANDOM_DELAY;

    //
    // Internal parameters
    //
    parameter WAIT_RANDOM = 1'b0;
    parameter POP_RECV_DATA = 1'b1;  

    //
    // Signal Declarations
    //

    // Memory to hold output vectors
    reg [BIT_WIDTH-1:0]     m_f[ENTRIES-1:0];

    // Output index
    reg [LOG2_ENTRIES-1:0]  index_f;
    reg [LOG2_ENTRIES-1:0]  index_next;
    reg                     index_en;

    // Random delay signals
    reg [31:0]              rand_delay_f;
    reg [31:0]              rand_delay_next;
    reg                     rand_delay_en;
    reg                     rand_delay_init;

    // Input queue signals
    wire [BIT_WIDTH-1:0]    inq_deq_bits;
    wire                    inq_full;
    wire                    inq_empty;
    reg                     inq_rdy;  
    
    // Fire signals
    reg                     verify_fire;

    // State register
    reg                     state_f;
    reg                     state_next;

    //
    // Synchronous Logic
    //

    // All flip-flops
    always @ (posedge clk)
    begin
        if (~rst_n)
        begin
            index_f         <= 0;
            rand_delay_f    <= 0;
            state_f         <= 0;
        end
        else
        begin
            index_f         <= index_next;
            rand_delay_f    <= rand_delay_next;
            state_f         <= state_next;
        end
    end 

    // Output checking logic
    always @ (posedge clk)
        if (verify_fire)
            `TEST_EQ("test_sink", m_f[index_f], inq_deq_bits, VERBOSITY)

    //
    // Combinational Logic
    //  

    // Output index next value
    always @ *
    begin
        index_next = index_f;
        if (index_en)
            index_next = index_f + 1;
    end

    // Random delay counter next value
    always @ *
    begin
        rand_delay_next = rand_delay_f;
        if (rand_delay_en)
            rand_delay_next = rand_delay_f - 1;
        else if (rand_delay_init)
            rand_delay_next = {$random} % RANDOM_DELAY;
    end  

    // Next state logic
    always @ *
    begin
        state_next = state_f;
        case (state_f)
            WAIT_RANDOM:
            begin
                if (!inq_empty && !done && (rand_delay_f == 0))
                    state_next = POP_RECV_DATA;
            end
            POP_RECV_DATA:
            begin
                if (inq_empty || done || (RANDOM_DELAY > 0))
                    state_next = WAIT_RANDOM;
            end 
        endcase
    end 

    // Enable bits
    always @ *
    begin
        index_en        = (state_f == POP_RECV_DATA) & ~inq_empty && ~done;
        rand_delay_en   = (state_f == WAIT_RANDOM) & (rand_delay_f > 0) && ~done;
        rand_delay_init = (state_f == POP_RECV_DATA) & (RANDOM_DELAY > 0) && ~done; 
    end

    // Other combinational signals
    always @ *
    begin
        inq_rdy         = (state_f == POP_RECV_DATA) & ~inq_empty && ~done;
        verify_fire     = (state_f == POP_RECV_DATA) & ~inq_empty && ~done;
        out_data_popped = (state_f == POP_RECV_DATA) & ~inq_empty && ~done;
    end 

    // Rdy and done signals
    always @ *
    begin
        rdy = ~(inq_full);
        done = ((m_f[index_f] === {BIT_WIDTH{1'bx}}) | (index_f == (ENTRIES - 1)));
    end

    //
    // Helper module instantiations
    //
    
    // Input queue
    test_infrstrct_fifo
    #(
        .BIT_WIDTH (BIT_WIDTH),
        .ENTRIES (16),
        .LOG2_ENTRIES (4)
    ) inQ
    (
        .clk (clk),
        .rst_n (rst_n),
        .din (bits),
        .wr_en (val),
        .rd_en (inq_rdy),
        .dout (inq_deq_bits),
        .full (inq_full),
        .empty (inq_empty),
        .val ()
    );

endmodule
