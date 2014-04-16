module QME
  module MapReduce
    # A delayed_job that allows for measure calculation by a delayed_job worker. Can be created as follows:
    #
    #     Delayed::Job.enqueue QME::MapRedude::MeasureCalculationJob.new(:measure_id => '0221', :sub_id => 'a', :effective_date => 1291352400, :test_id => xyzzy)
    #
    # MeasureCalculationJob will check to see if a measure has been calculated before running the calculation. It does
    # this by creating a QME::QualityReport and asking if it has been calculated. If so, it will complete the job without
    # running the MapReduce job.
    #
    # When a measure needs calculation, the job will create a QME::MapReduce::Executor and interact with it to calculate
    # the report.
    class MeasureCalculationJob
      include DatabaseAccess
      attr_accessor :test_id, :measure_id, :sub_id, :effective_date, :filters

      def initialize(options)
        @measure_id = options['measure_id']
        @sub_id = options['sub_id']
        @options = options
      end
      
      def perform
        full_options = @options.deep_dup
#        provider_list = get_db()['providers'].find(:last_name => "Adams RES") #.distinct("_id").map {|x| x.to_s}
				full_options.merge!({:filters => {:providers => nil}})
        
        qr = QualityReport.new(@measure_id, @sub_id, @options)
        fqr = QualityReport.new(@measure_id, @sub_id, full_options)
        
        # aggregate calculation
        if fqr.calculated?
          completed("#{@measure_id}#{@sub_id} aggregate has already been calculated")
          fresult = fqr.result
        else
          fmap = QME::MapReduce::Executor.new(@measure_id, @sub_id, full_options.merge('start_time' => Time.now.to_i))
          if !fqr.patients_cached?
            tick('Starting Full MapReduce')
            fmap.map_records_into_measure_groups
            tick('Full MapReduce complete')
          end
          
          tick('Calculating group totals for aggregate')
          fresult = fmap.count_records_in_measure_groups
          completed("#{@measure_id}#{@sub_id}: p#{fresult[QME::QualityReport::POPULATION]}, d#{fresult[QME::QualityReport::DENOMINATOR]}, n#{fresult[QME::QualityReport::NUMERATOR]}, excl#{fresult[QME::QualityReport::EXCLUSIONS]}, excep#{fresult[QME::QualityReport::EXCEPTIONS]}")
        end
        
        # main calculation
        if qr.calculated?
          completed("#{@measure_id}#{@sub_id} has already been calculated")
        else
          map = QME::MapReduce::Executor.new(@measure_id, @sub_id, @options.merge('start_time' => Time.now.to_i))
          if !qr.patients_cached?
            tick('Starting MapReduce')
            map.map_records_into_measure_groups
            tick('MapReduce complete')
          end
          
          tick('Calculating group totals')
          result = map.count_records_in_measure_groups(fresult[QME::QualityReport::NUMERATOR], fresult[QME::QualityReport::DENOMINATOR])
          completed("#{@measure_id}#{@sub_id}: p#{result[QME::QualityReport::POPULATION]}, d#{result[QME::QualityReport::DENOMINATOR]}, n#{result[QME::QualityReport::NUMERATOR]}, excl#{result[QME::QualityReport::EXCLUSIONS]}, excep#{result[QME::QualityReport::EXCEPTIONS]}")
        end
        result
      end

      def completed(message)
        
      end

      def tick(message)
        
      end
    end
  end
end
