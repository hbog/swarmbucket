require 'net/http'

class SwarmHTTP

    class Net::HTTPGenericRequest                                                   
        def uri=(uri)                                                               
            raise ArgumentError, "uri is not URI" unless URI === uri                
            @path = uri.request_uri                                                 
            raise ArgumentError, "no HTTP request path given" unless @path          
            @uri = uri                                                              
            host = @uri.hostname.dup                                                
            host << ":".freeze << @uri.port.to_s if @uri.port != @uri.default_port  
            self['Host'] ||= host                                                   
        end                                                                         
    end                           

    def initialize(domain, bucket)
        @baseurl = "http://#{domain}/#{bucket}"
    end

    def execute(req)                                                                
        res = Net::HTTP.start(req.uri.hostname, req.uri.port) do |http|             
            http.request(req)                                                       
        end                                                                         
        return res unless Net::HTTPRedirection === res                              
        location = res['location']                                                  
        req.uri = URI location                                                      
        execute(req)                                                                
    end                                                                             

    def get(name)                                                                   
        uri = URI("#{@baseurl}/#{name}")             
        req = Net::HTTP::Get.new(uri)                                               
        execute(req)                                                                
    end                                                                             

    def head(name)                                                                  
        uri = URI("#{@baseurl}/#{name}")             
        req = Net::HTTP::Head.new(uri)                                              
        execute(req)                                                                
    end                                                          

    def present?(name)                                                                  
        uri = URI("#{@baseurl}/#{name}")             
        req = Net::HTTP::Head.new(uri)                                              
        Net::HTTPSuccess === execute(req)
    end                                                          
end

