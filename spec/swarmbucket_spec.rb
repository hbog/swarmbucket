require_relative '../swarmbucket'


# Respondi, cycling through responses
# saving the requests in the array @httprequests
def respond req, responses
    @httprequests ||= []
    n = @httprequests.length % responses.length # cycle through the responsed
    @httprequests << req.dup
    responses[n]
end

describe SwarmBucket do
    let (:swarmhttp) { SwarmBucket.new domain: 'domain', bucket: 'bucket',
                       username: 'username', password: 'password'}
    let (:httpsuccess) { Net::HTTPSuccess.new(1.1, '200', 'OK')}
    let (:httpredirect) { Net::HTTPRedirection.new(1.1, '301', 'Moved Permanently')}
    let (:httpnotfound) { Net::HTTPNotFound.new(1.1, '404', 'Not Found')}
    let (:httpunauthorized) { Net::HTTPUnauthorized.new(1.1, '401', 'Unauthorized')}
    let (:http) { instance_spy 'Net:HTTP'}
    #let! (:@httprequests) {[]}

    # Mock the http redirection
    # and collect the request objects
    before :each do
        allow(Net::HTTP).to receive(:start).and_return(http)
        allow(httpredirect).to receive(:[])
        .with('location') { 'http://newhost/newpath?param' }
    end

    shared_examples 'http_request' do |method,n|
        before :each do
            @response = do_request
        end
        it 'opens a HTTP connection' do
            expect(Net::HTTP).to have_received(:start)
            .with('domain',80).once
        end
        it 'closes a HTTP connection' do
            expect(http).to have_received(:finish).exactly(n).times
        end
        it 'has the correct request method' do
            expect(@httprequests.map &:method)
            .to start_with(method.to_s.upcase)
            expect(@httprequests.map &:method)
            .to end_with(method.to_s.upcase)
        end
        it 'has the correct request path' do
            expect(@httprequests.map &:path)
            .to start_with '/bucket/objectname'
        end
        it 'returns the response object' do
            expect(@response).to be(httpsuccess)
        end
    end
    shared_examples "http_redirected_request" do |method|
        context 'when not redirected' do
            before :each do
                allow(http).to receive(:request) do |req|
                    respond req, [httpsuccess]
                end
            end
            include_examples 'http_request', method, 1
        end
        context 'when redirected twice' do
            before :each do
                allow(http).to receive(:request) do |req|
                    respond req, [httpredirect, httpredirect, httpsuccess]
                end
            end
            include_examples 'http_request', method, 3
            it 'follows the redirection' do
                expect(Net::HTTP).to have_received(:start)
                .with('newhost',80).twice
                expect(@httprequests.map &:path)
                .to eq ['/bucket/objectname','/newpath?param','/newpath?param']
            end
        end
        context 'when too many redirects' do
            before :each do
                allow(http).to receive(:request) do |req|
                    respond req, [httpredirect, httpredirect, httpredirect, httpsuccess]
                end
            end
            it  do
                expect {do_request}.to raise_error RuntimeError
            end
        end
        context "when swarm returns 'unauthorized'" do
            before :each do
                allow(http).to receive(:request) do |req|
                    respond req, [httpunauthorized, httpsuccess]
                end
                allow(httpunauthorized).to receive(:[]).with('www-authenticate').and_return(
                    'Digest realm="domain", nonce="nonce", opaque="opaque", stale=false, qop="auth", algorithm=MD5')
                do_request
            end
            subject { @httprequests.last }
            it 'adds an digest authorization header' do
                expect(subject['authorization']).to match(
                    'Digest username="username", realm="domain", algorithm=MD5, qop=auth, uri="/bucket/objectname",.*, opaque="opaque"')
            end
        end
        context 'when unauthorized and authorization fails, the response' do
            before :each do
                allow(http).to receive(:request).and_return(httpunauthorized, httpunauthorized, httpsuccess)
                allow(httpunauthorized).to receive(:[]).with('www-authenticate').and_return(
                    'Digest realm="domain", nonce="nonce", opaque="opaque", stale=false, qop="auth", algorithm=MD5')
            end
            subject { do_request }
            it { is_expected.to be httpunauthorized }
        end
    end

    shared_examples 'present?' do
        context 'when the object does not exist' do
            before :each do
                allow(http).to receive(:request).and_return(httpnotfound)
            end
            it { is_expected.to be false }
        end
        context 'when the object exists' do
            before :each do
                allow(http).to receive(:request) do |req|
                    respond req, [httpredirect, httpsuccess]
                end
            end
            context 'without a lifepoint' do
                before :each do
                    allow(httpsuccess).to receive(:[])
                        .with('lifepoint') { nil }
                end
                it { is_expected.to be true }
            end
            context 'with a delete lifepoint' do
                before :each do
                    allow(httpsuccess).to receive(:[])
                        .with('lifepoint')
                        .and_return "[Wed, 29 Jun 2016 13:30:39 GMT] reps:16:4 deletable=True, [] delete"
                end
                it { is_expected.to be 14400 }
            end
            context 'with a non-delete lifepoint' do
                before :each do
                    allow(httpsuccess).to receive(:[])
                        .with('lifepoint')
                        .and_return "[Wed, 29 Jun 2016 13:30:39 GMT] reps:16:4 deletable=True, [] reps:2"
                end
                it { is_expected.to be true }
            end
            context 'with mutliple lifepoints' do
                before :each do
                    allow(httpsuccess).to receive(:[])
                        .with('lifepoint') {[
                    "[Wed, 29 Jun 2016 12:30:39 GMT] reps:16:4 deletable=False",
                    "[Wed, 29 Jun 2016 13:30:39 GMT] reps:2 deletable=True",
                    "[] delete"
                    ].join ','}
                end
                it { is_expected.to be 14400 }
            end
        end
    end

    context '#new' do
        it 'sets the baseurl' do
            expect(swarmhttp.baseurl).to eq 'http://domain/bucket'
        end
    end

    [:get, :head, :post].each do |method|
        context "\##{method}" do
            it_behaves_like("http_redirected_request", method) do
                args = case method
                       when :get, :head
                           [ method, 'objectname' ]
                       when :post
                           [method, 'objectname','body','content/type' ]
                       end
                let(:do_request) { swarmhttp.send *args }
            end
        end
    end
    context 'lifepoints' do
        before :each do
            allow(http).to receive(:request) do |req|
                respond req, [httpredirect, httpsuccess]
            end
            # Set current time during test at 2016-06-29 11:30:39 +0200
            allow(Time).to receive(:now) { Time.at 1467192639 }
        end
        context '#post' do
            subject { @httprequests.last }
            context 'when ttl is not specified' do
                before :each do
                    swarmhttp.post 'objectname','body','content/type'
                end
                it 'sets the content-type header' do
                    expect(subject['Content-Type']).to eq 'content/type'
                end
                it 'does not set a life-point header' do
                    expect(subject['lifepoint']).to be_nil
                end
            end
            context 'when ttl is specified' do
                before :each do
                    swarmhttp.post 'objectname','body','content/type', 14400
                end
                it 'sets a lifepoint header' do
                    expect(subject['lifepoint'])
                    .to match /\[Wed, 29 Jun 2016 13:30:39 GMT\] \S* deletable=True, \[\] delete/
                end
                it 'sets the content-type header' do
                    expect(subject['Content-Type']).to eq 'content/type'
                end
            end
        end
        context '#present?' do
            subject { swarmhttp.present? 'objectname' }
            include_examples 'present?'
        end

    end
end
