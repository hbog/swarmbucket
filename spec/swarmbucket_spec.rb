require_relative '../swarmbucket'

describe SwarmBucket do
    let! (:swarmhttp) { SwarmBucket.new 'domain','bucket' }
    let (:httpsuccess) { Net::HTTPSuccess.new(1.1, '200', 'OK')}
    let (:httpredirect) { Net::HTTPRedirection.new(1.1, '301', 'Moved Permanently')}
    let (:httpnotfound) { Net::HTTPNotFound.new(1.1, '404', 'Not Found')}
    let (:http) { double 'http'}
    let (:http1) { double 'http1'}
    let (:http2) { double 'http2'}
    let (:http3) { double 'http3'}
    let! (:httprequests) {[]}

    # Mock the http redirection
    # and collect the request objects
    before :each do
        allow(httpredirect).to receive(:[])
        .with('location')
        .and_return('http://newhost/newpath?param1',
                    'http://newerhost/newerpath?param2')
        allow(http).to receive(:request) do |req|
            httprequests << req.dup
        end
    end

    shared_examples 'http_request' do |method|
        it 'opens a HTTP connection' do
            expect(Net::HTTP).to have_received(:start)
            .with('domain',80).once
        end
        it 'has the correct request method' do
            expect(httprequests.map &:method)
            .to start_with(method.to_s.upcase)
            expect(httprequests.map &:method)
            .to end_with(method.to_s.upcase)
        end
        it 'has the correct request path' do
            expect(httprequests.map &:path)
            .to start_with '/bucket/objectname'
        end
        it 'returns the response object' do
            expect(@response).to be(httpsuccess)
        end
    end
    shared_examples "http_redirected_request" do |method|
        context 'when not redirected' do
            before :each do
                allow(Net::HTTP).to receive(:start)
                .and_return(httpsuccess)
                .and_yield(http)
                @response = do_request
            end
            include_examples 'http_request', method
        end
        context 'when redirected twice' do
            before :each do
                allow(Net::HTTP).to receive(:start)
                .and_return(httpredirect,httpredirect,httpsuccess)
                .and_yield(http)
                @response = do_request
            end
            include_examples 'http_request', method
            it 'follows the redirection' do
                expect(Net::HTTP).to have_received(:start)
                .with('newhost',80).once
                expect(Net::HTTP).to have_received(:start)
                .with('newerhost',80).once
                expect(httprequests.map &:path)
                .to eq ['/bucket/objectname','/newpath?param1','/newerpath?param2']
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
    context 'block' do
        # refacter and dry-up
        before :each do
            @yields = []
            allow(Net::HTTP).to receive(:start).with('domain', 80 )
            .and_yield(http1)
            allow(Net::HTTP).to receive(:start).with('newhost', 80 )
            .and_yield(http2)
            allow(Net::HTTP).to receive(:start).with('newerhost', 80 )
            .and_yield(http3)
            allow(http1).to receive(:request) do |req|
                httprequests.unshift double(path: '/bucket/objectname')
            end.and_yield httpredirect
            allow(http2).to receive(:request) do |req|
                httprequests.unshift double(path: '/newpath?param1')
            end.and_yield(httpredirect)
            allow(http3).to receive(:request) do |req|
                httprequests.unshift double(path: '/newerpath?param2')
            end.and_yield(httpsuccess)
            swarmhttp.get 'objectname' do |resp|
                @yields << resp
            end
        end
        it 'opens a HTTP connection' do
            expect(Net::HTTP).to have_received(:start)
            .with('domain',80).once
        end
        xit 'has the correct request method' do
            expect(httprequests.map &:method)
            .to start_with(method.to_s.upcase)
            expect(httprequests.map &:method)
            .to end_with(method.to_s.upcase)
        end
        it 'has the correct request path' do
            expect(httprequests.map &:path)
            .to start_with '/bucket/objectname'
        end
        it 'does not return the response object' do
            expect(@response).to be_nil
        end
        it 'only yields on HTTPSuccess' do
            expect(@yields).to eq [httpsuccess]
        end
        it 'follows the redirection' do
            expect(Net::HTTP).to have_received(:start)
            .with('newhost',80).once
            expect(Net::HTTP).to have_received(:start)
            .with('newerhost',80).once
            expect(httprequests.map &:path)
            .to eq ['/bucket/objectname','/newpath?param1','/newerpath?param2']
        end
    end
    context 'lifepoints' do
        before :each do
            allow(Net::HTTP).to receive(:start).and_return(httpredirect,httpsuccess)
            .and_yield(http)
            # Set current time during test at 2016-06-29 11:30:39 +0200
            allow(Time).to receive(:now) { Time.at 1467192639 }
        end
        context '#post' do
            subject { httprequests.last }
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
            context 'when the object does not exist' do
                before :each do
                    allow(Net::HTTP).to receive(:start).and_return(httpnotfound)
                    .and_yield(http)
                end
                it { is_expected.to be false }
            end
            context 'when the object exists' do
                before :each do
                    allow(Net::HTTP).to receive(:start).and_return(httpredirect,httpsuccess)
                    .and_yield(http)
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
    end
end
