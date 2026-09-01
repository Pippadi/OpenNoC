/////////////////////////////////////////////////////////////////////////////////////////////
//File Name : switch.v                                                                     //
//Description : Bufferless router following XY routing                                     //
/////////////////////////////////////////////////////////////////////////////////////////////

module switch
#(
    parameter x_coord = 'd0,
    parameter y_coord = 'd0,
    parameter data_width = 32,
    parameter x_size = 1,
    parameter y_size = 1,
    parameter total_width = (x_size+y_size+data_width)
)
(
    input wire clk,
    input wire rstn,
    input wire i_ready_r,
    input wire i_ready_t,
    input wire i_ready_pe,
    input wire i_valid_l,
    input wire i_valid_b,
    input wire i_valid_pe,
    output wire o_ready_l,
    output wire o_ready_b,
    output reg  o_ready_pe,
    output reg o_valid_r,
    output reg o_valid_t,
    output reg o_valid_pe,
    input wire [total_width-1:0] i_data_l,
    input wire [total_width-1:0] i_data_b,
    input wire [total_width-1:0] i_data_pe,
    output reg [total_width-1:0] o_data_r,
    output reg [total_width-1:0] o_data_t,
    output reg [total_width-1:0] o_data_pe
);

wire leftToPe;
wire bottomToPe;
wire peToPe;
wire leftToRight;
wire leftToTop;
wire bottomToRight;
wire bottomToTop;
wire peToTop;
wire peToRight;

assign o_ready_l = 1'b1;
assign o_ready_b = 1'b1;

assign leftToPe = ((i_data_l[x_size-1:0]==x_coord) & (i_data_l[x_size+y_size-1:x_size]==y_coord) & i_valid_l);
assign leftToRight = ((i_data_l[x_size-1:0]!=x_coord) & i_valid_l);
assign leftToTop = (i_data_l[x_size-1:0]==x_coord) & (i_data_l[x_size+y_size-1:x_size]!=y_coord) & i_valid_l;
assign bottomToPe = (i_data_b[x_size-1:0]==x_coord) & (i_data_b[x_size+y_size-1:x_size]==y_coord) & i_valid_b;
assign bottomToRight = (i_data_b[x_size+y_size-1:x_size]==y_coord) & (i_data_b[x_size-1:0]!=x_coord) & i_valid_b;// ? 1'b1 : 1'b0;
assign bottomToTop = (i_data_b[x_size+y_size-1:x_size]!=y_coord ) & i_valid_b;
assign peToPe = ((i_data_pe[x_size-1:0]==x_coord) & (i_data_pe[x_size+y_size-1:x_size]==y_coord) & i_valid_pe & o_ready_pe);
assign peToRight = ((i_data_pe[x_size-1:0]!=x_coord) & i_valid_pe & o_ready_pe);
assign peToTop = (~peToRight & (i_data_pe[x_size+y_size-1:x_size]!=y_coord) & i_valid_pe & o_ready_pe);

wire route_b_to_r =
    bottomToRight |
    (bottomToPe & peToPe & ~leftToRight) |
    (bottomToPe & ~i_ready_pe & ~leftToRight);
wire route_l_to_r =
    (leftToRight & ~bottomToRight) |
    (bottomToTop & leftToTop) |
    (leftToPe & peToPe & ~bottomToRight) |
    (leftToPe & bottomToPe) |
    (leftToPe & ~i_ready_pe & ~bottomToRight);
wire route_pe_to_r =
    (peToRight & ~bottomToRight & ~leftToRight) |
    (peToTop & leftToTop) |
    (peToTop & bottomToTop) |
    (peToPe & ~i_ready_pe & ~bottomToRight);

wire route_b_to_t =
    bottomToTop |
    (leftToPe & peToTop & bottomToRight) |
    (bottomToPe & ~i_ready_pe & leftToRight) |
    (bottomToPe & peToPe & leftToRight);
wire route_l_to_t =
    (leftToTop & ~bottomToTop) |
    (leftToRight & bottomToRight) |
    (leftToPe & bottomToRight & ~i_ready_pe) |
    (leftToPe & peToRight & ~i_ready_pe) |
    (leftToPe & peToPe & bottomToRight);
wire route_pe_to_t =
    (peToTop & ~leftToTop & ~bottomToTop) |
    (peToRight & bottomToRight) |
    (peToRight & leftToRight) |
    (peToPe & ~i_ready_pe & bottomToRight) |
    (peToPe & ~i_ready_pe & leftToRight);

always @(posedge clk) begin
    if (~rstn) begin
        o_ready_pe <= 0;
    end else begin
        //If there are no packets to either right or top, we can accept data from PE
        //If packets have to be sent to both out ports, will have to back pressure the PE
        o_ready_pe <= (~leftToRight & ~leftToTop & ~leftToPe) | (~bottomToTop & ~bottomToRight & ~bottomToPe);
    end
end

always @(posedge clk) begin
	if (~rstn) begin
		o_valid_r <=1'b0;
		o_data_r <= {total_width{1'b0}};
	end else begin
		if (route_b_to_r)
			o_data_r <= i_data_b;

		if (route_l_to_r)
            o_data_r <= i_data_l;

        if (route_pe_to_r)
            o_data_r <= i_data_pe;

        o_valid_r <= route_b_to_r | route_l_to_r | route_pe_to_r;
	end
end


always @(posedge clk) begin
	if (~rstn) begin
		o_valid_t <= 1'b0;
		o_data_t <= {total_width{1'b0}};
	end else begin
	    if (route_b_to_t)
            o_data_t <= i_data_b;

        if (route_l_to_t)
            o_data_t <= i_data_l;

        if (route_pe_to_t)
            o_data_t <= i_data_pe;

        o_valid_t <= route_b_to_t | route_l_to_t | route_pe_to_t;
	end
end

always @(posedge clk) begin
    if (~rstn) begin
		o_valid_pe <= 1'b0;
    end else begin
        if (peToPe & i_ready_pe) begin
            o_data_pe <= i_data_pe;
            o_valid_pe <= 1'b1;
        end
        else if (bottomToPe & i_ready_pe) begin
            o_data_pe <= i_data_b;
            o_valid_pe <= 1'b1;
        end
        else if (leftToPe & i_ready_pe) begin
            o_data_pe <= i_data_l;
            o_valid_pe <= 1'b1;
        end
        else if (o_valid_pe & ~i_ready_pe)
            o_valid_pe <= 1'b1;
        else
            o_valid_pe <=1'b0;
    end
end

endmodule
