# SwarmBucket is a thin wrapper around Net:HTTP to facilitate access to bucket
# content as named objects in a Caringo Swarm Object Store.
# It handles the Swarm specifics of the HTTP protocol such as redirection,
# an append method and lifepoint headers
# The methods typically return raw Net::HTTP::Response objects.

require 'net/http'

class SwarmBucket

    attr_reader :baseurl

    #
    # add an 'APPEND' request type to Net::HTTP
    class Net::HTTP::Append < Net::HTTPRequest
             METHOD = 'APPEND'
             REQUEST_HAS_BODY = true
             RESPONSE_HAS_BODY = true
    end

    # extend the HTTP::GenericRequest class with an uri setter
    # this allows to re-use a request object during a HTTP redirect
    # in a generic way by overwriting the uri
    # (and keeping the headers, method, etc)
    class Net::HTTPGenericRequest
        def uri=(uri)
            raise ArgumentError, "uri is not URI" unless URI === uri
            @uri = uri.dup
            @path = @uri.request_uri
            # update the host header if it was set
            if self['Host']
                host = @uri.hostname.dup
                host << ":".freeze << @uri.port.to_s if @uri.port != @uri.default_port
                self['Host'] = host
            end
        end
        @uri
    end

    def initialize(domain, bucket)
        @baseurl = "http://#{domain}/#{bucket}"
    end

    def get(name)
        request = Net::HTTP::Get.new(swarmuri name)
        execute request
    end

    def head(name)
        request = Net::HTTP::Head.new(swarmuri name)
        execute request
    end

    def post(name, body, contenttype, ttl=nil)
        request = Net::HTTP::Post.new(swarmuri name)
        request.body = body
        request['Content-Type'] = contenttype
        if ttl
            expires = (Time.now + ttl)
            .gmtime.strftime '%a, %d %b %Y %H:%M:%S GMT'
            request['lifepoint'] = [
                "[#{expires}] reps=16:4, deletable=True",
                "[] delete"
            ]
        end
        execute request
    end

    # Check if an object exists
    # returns
    #    - false when the object does not exist
    #    - true when object exists without a delete lifepoint
    #    - the ttl (Fixnum) when the object exists with a delete lifepoint
    def present?(name)
        request = Net::HTTP::Head.new(swarmuri name)
        response = execute request
        return false unless Net::HTTPSuccess === response
        myttl = ttl response
        myttl.nil? ? true : myttl
    end

    private

    def execute(request)
        response = Net::HTTP.start(request.uri.hostname, request.uri.port) do |http|
            http.request request
        end
        return response unless Net::HTTPRedirection === response
        # If we resceive a redirect, update the request uri to the given
        # location and re-issue the request
        location = response['location']
        request.uri = URI location
        execute request
    end

    def swarmuri(name)
        URI "#{@baseurl}/#{name}"
    end

    # Returns the ttl of the object when a delete lifepoint is set
    # Otherwise return nil
    def ttl (response)
        DateTime.httpdate($1).to_time.to_i - Time.now.gmtime.to_i if 
        response['lifepoint'] =~ /.*\[(.+?)\].*delete.*/
    end

end
