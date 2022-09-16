BEGIN {
  # CONFIGURABLE
  slash = "/"
  home_dir = "~" # Should be absolute, not relative
  r_dir = ""
  bash_dir = slash "bin" slash "bash"
  s3_dir = "s3://cronan-fdm-eglin-simulations"
  raw_ud_log_path = "user_data_log.txt"

  # FIXED
  instance_count = 0
  ud_log_path = home_dir slash raw_ud_log_path

  # WINDOWS: r_dir = "\"" slash "Program Files" slash "R" slash "R-3.4.2" slash "bin" slash "bash.exe"

}

{ if (NR==1) {
   header = $0
  } else {
   file = sim_id"/user_data_"NR".ud"
   instance_count = instance_count + $1

   # If Windows, print <script> tag
   # https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2-windows-user-data.html
   # print "<script>" > file;

   print "#!" bash_dir > file;

   print "echo \"Launched user data script...\" >> " ud_log_path > file;

   # Export environmental variables
   print "export LC_ALL=en_US.UTF-8" > file;  # https://bugs.python.org/issue18378
   print "export LANG=en_US.UTF-8" > file;    # see above
   print "export AWS_DEFAULT_REGION=us-west-2" > file;

   print "echo \"Set environmental variables...\" >> " ud_log_path > file;

   # Pulls repo from Github
   print "cd " home_dir > file;
   print "curl -L https://www.github.com/jcronanuw/EglinAirForceBase/archive/master.zip > " home_dir slash "eafb.zip" > file;
   print "unzip " home_dir slash "eafb.zip" > file;
   print "cd " home_dir slash "EglinAirForceBase-master" > file;

   print "echo \"Pulled repo from Github...\" >> " ud_log_path > file;

   # Create run id for each separate host
   print "RUN_ID=$(eval echo $(curl -s http://169.254.169.254/latest/meta-data/instance-id) | tail -c 5)" > file;

   print "echo \"Created run id [$RUN_ID]...\" >> " ud_log_path > file;

   # Change key for host in EC2
   print "aws ec2 create-tags --resources $(eval echo $(curl -s http://169.254.169.254/latest/meta-data/instance-id)) --tags Key=Name,Value=FDM_Instance_" sim_id "_$RUN_ID" > file;

   print "echo \"Tagged EC2 instance...\" >> " ud_log_path > file;

   # Add appropriate folders and move log file
   print "mkdir " home_dir slash sim_id > file;
   print "mkdir " home_dir slash sim_id slash "$RUN_ID" > file;
   print "input_path=" home_dir slash "EglinAirForceBase-master" slash  > file;
   print "output_path=" home_dir slash sim_id slash "$RUN_ID" slash > file;
   print "r_output_path=" home_dir slash sim_id slash "$RUN_ID" slash "r_log.txt" > file;
   temp_ud_log_path = ud_log_path
   ud_log_path = home_dir slash sim_id slash "$RUN_ID" slash raw_ud_log_path
   print "mv " temp_ud_log_path " " ud_log_path > file;

   print "echo \"Created appropriate folders and moved user data log file...\" >> " ud_log_path > file;

   # Create host-specific simulation parameters csv file
   print "echo \"" header ",sim_id,run_id,input_path,output_path,r_output_path\" > host_sim_params.csv" > file;
   print "echo \"" $0 "," sim_id ",$RUN_ID,$input_path,$output_path,$r_output_path\" >> host_sim_params.csv" > file;

   print "echo \"Created host sim parameter file...\" >> " ud_log_path > file;

   print "echo \"Starting R script...\" >> " ud_log_path > file;
   print "echo >> " ud_log_path > file;
   print "echo \"Errors from R (stderr stream):\" >> " ud_log_path > file;

   # Run R script
   print r_dir "Rscript sef_FDM_v2.0.r >> " ud_log_path " 2>&1" > file;
   print "r_success=$?" > file;
   print "echo >> " ud_log_path > file;
   print "echo \"Finished R script...\" >> " ud_log_path > file;

   # Check status after completion of script (0=success=true, 1=failed=false)

   print "echo \"R script exit code:\" $r_success >> " ud_log_path > file;

   # Result folder pushed to S3 (regardless of success or fail)
   print "cd " home_dir slash sim_id slash "$RUN_ID" > file;
   print "for file in *; do " > file;
   print "  aws s3 cp $file " s3_dir "/" sim_id "/$RUN_ID/$file" > file;
   print "done" > file;

   print "echo \"Pushed result folder to S3...\" >> " ud_log_path > file;

   print "if [ $r_success -eq 0 ]; then" > file;

   print "  echo \"R script success, terminating instance...\" >> " ud_log_path > file;

   #   Terminate this instance (if success)
   print "  aws ec2 terminate-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id) --region us-west-2" > file;

   print "else" > file;

   #   Send email with instance id, output files (and error message) (if fail)
   print "  aws ses send-email --subject \"R Failure for Simulation $RUN_ID " sim_id "\" --text \"There was an error for $RUN_ID and the R script stopped. To access this simulation use: ssh -i wildfire-simulation.pem ubuntu@$(curl -s http://169.254.169.254/latest/meta-data/public-hostname). Access log in " s3_dir "/$RUN_ID/" sim_id ". Disturbance loop variables are: years: a; treatment number: b; treatment block: cc; treatment expansion: d; wildfire number: e; wildfire block: f; unsuppressed wildfire expansion: g; block and burn expansion number: h.  \" --to jcronan@uw.edu --from jcronan@uw.edu" > file;

   print "echo \"Sent failure email...\" >> " ud_log_path > file;
   print "echo \"R script failure, stopping (but not terminating) instance for later analysis...\" >> " ud_log_path > file;

   #   Stop instance (if fail)
   # print "  aws ec2 stop-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id)" > file;
   print "fi" > file;

   # Print end script tag for Windows
   # WINDOWS: print "</script>" > file;
  }
}

END { print "\nSimulation \"" sim_id "\" will launch " instance_count " EC2 instances."}
