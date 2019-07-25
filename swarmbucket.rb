# SwarmBucket is a thin wrapper around Net:HTTP to facilitate access to bucket
# content as named objects in a Caringo Swarm Object Store.
# It handles the Swarm specifics of the HTTP protocol such as redirection,
# an append method and lifepoint headers
# The methods typically return raw Net::HTTP::Response objects.

require 'date'
require 'net/http'
require 'net/http/digest_auth'

class SwarmBucket

    class Request

        def initialize request, username=nil, password=nil
            @request = request
            @username = username
            @password = password
            @redirections = 0
            connect
        end

        def connect
            @http = Net::HTTP.start @request.uri.hostname, @request.uri.port
        end

        def disconnect
            @http.finish
        end

        def reconnect
            disconnect
            connect
        end

        def execute
            response = @http.request @request
            case response
            when Net::HTTPRedirection
                @redirections += 1
                raise 'too many redirects' if @redirections > 2
                # If we resceive a redirect, update the request uri to the given
                # location and re-issue the request
                location = response['location']
                @request.uri = URI location
                reconnect
                execute
            when Net::HTTPUnauthorized
                # retrut the request with a digest authorization header unless
                # we already did,
                return response if @request['Authorization']
                digest_auth = Net::HTTP::DigestAuth.new
                @request.uri.user = @username
                @request.uri.password = @password
                @request['Authorization'] = digest_auth.auth_header @request.uri,
                    response['www-authenticate'], @request.method
                execute
            else
                disconnect
                response # return the response from within the recursion
            end
        end
    end

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

    def initialize domain:, bucket:, username: nil, password: nil
        @baseurl = "http://#{domain}/#{bucket}"
        @username = username
        @password = password
    end

    def submit request
        SwarmBucket::Request.new(request, @username, @password).execute
    end

    def get name
        request = Net::HTTP::Get.new(swarmuri name)
        submit request
    end

    def copy name, headers
        parameter_defaults = {
          preserve: true,
          gencontentmd5: true
        }
        request = Net::HTTP::Copy.new(swarmuri(name, parameter_defaults))
        headers.each { |k,v| request[k] = v }
        submit request
    end

    def head name
        request = Net::HTTP::Head.new(swarmuri name, {verbose: true})
        submit request
    end

    def delete name
        request = Net::HTTP::Delete.new(swarmuri name)
        submit request
    end

    def post name, body, contenttype, ttl=nil
        request = Net::HTTP::Post.new(swarmuri name)
        request.body = body
        request['Content-Type'] = contenttype
        request['Castor-Authorization'] = 'post=owner@, change=owner@'
        if ttl
            expires = (Time.now + ttl)
            .gmtime.strftime '%a, %d %b %Y %H:%M:%S GMT'
            request['lifepoint'] = [
                "[#{expires}] reps=16:4, deletable=True",
                "[] delete"
            ]
        end
        submit request
    end

    # Check if an object exists
    # returns
    #    - false when the object does not exist
    #    - true when object exists without a delete lifepoint
    #    - the ttl (Fixnum) when the object exists with a delete lifepoint
    def present? name
        response = head name
        return false unless Net::HTTPSuccess === response
        ttl = DateTime.httpdate($1).to_time.to_i - Time.now.gmtime.to_i if
        response['lifepoint'] =~ /.*\[(.+?)\].*delete.*/
        ttl.nil? ? true : ttl
    end

    def swarmuri name, params = nil
        uri = URI "#{@baseurl}/#{name}"
        uri.query = URI.encode_www_form(params) unless (params.nil? || params.empty?)
        uri
    end

end
