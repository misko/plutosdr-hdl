// Compare the original authorization at the actual writer-ready boundary.
wire product_original_accept = dut.original_product_commit_authorized;
integer product_checks=0,product_differences=0,product_publications=0,product_reader_edges=0;
reg product_prior_request=0;
task check_product_publication;
begin
 if(dut.fast_running === 1'b1 && dut.product_bank_ready === 1'b1)begin
   if(dut.product_bank_valid !== 1'b0)$fatal(1,"product ownership overlap");
   if(dut.product_commit_authorized !== product_original_accept)
     $fatal(1,"product writer authorization mismatch");
 end
 if(dut.product_bank_valid !== 1'b0 && dut.product_commit_authorized === 1'b1)
   $fatal(1,"reader-owned or unknown bank permitted new publication");
 if(dut.product_commit_authorized !== product_original_accept)
   product_differences=product_differences+1;
 if(dut.product_bank_valid === 1'b1)product_reader_edges=product_reader_edges+1;
 product_checks=product_checks+1;
end
endtask
always @(posedge fft_clk)begin
 check_product_publication;
 #0.001;check_product_publication;
 if(dut.fast_running === 1'b1 && dut.product_owner_request !== product_prior_request)
   product_publications=product_publications+1;
 product_prior_request=dut.product_owner_request;
end
task report_product_publication;
begin
 $display("PRODUCT_PUBLICATION_PASS checks=%0d publications=%0d reader_edges=%0d authorization_differences=%0d writer_exact=1",
   product_checks,product_publications,product_reader_edges,product_differences);
end
endtask
