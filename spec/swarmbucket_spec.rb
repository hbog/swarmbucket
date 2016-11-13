require_relative '../swarmbucket'

describe SwarmBucket do
    let (:swarmhttp) { SwarmBucket.new 'domain','bucket' }
    let (:httpresponse) { double 'response' }
    let! (:httprequests) {[]}

    # Mock the http connection returning httpresponse
    # and collect the request objects
    before :each do
        http = double 'http'
        allow(Net::HTTP).to receive(:start) { httpresponse }
        .and_yield(http)
        allow(http).to receive(:request) do |req|
            httprequests << req.dup
        end
    end

    shared_examples 'http_request' do |method|
        before :each do
            @response = do_request
        end
        it 'opens a HTTP connection' do
            expect(Net::HTTP).to have_received(:start)
            .with('domain',80)
        end
        it 'has the correct request method' do
            expect(httprequests.map &:method)
            .to start_with(method.to_s.upcase)
            expect(httprequests.map &:method)
            .to end_with(method.to_s.upcase)
        end
        it 'has the correct request path' do
            expect(httprequests.map &:path)
            .to include '/bucket/objectname'
        end
        it 'returns the response object' do
            expect(@response).to be(httpresponse)
        end
    end
    shared_examples "http_redirected_request" do |method|
        context 'when not redirected' do
            before :each do
                expect(Net::HTTPRedirection).to receive(:===)
                .with(httpresponse) { false }
            end
            include_examples 'http_request', method
        end
        context 'when redirected twice' do
            before :each do
                expect(Net::HTTPRedirection).to receive(:===)
                .with(httpresponse).and_return(true, true, false)
                allow(httpresponse).to receive(:[])
                .with('location') { 'http://newhost/newpath?param' }
            end
            include_examples 'http_request', method
            it 'follows the redirection' do
                expect(Net::HTTP).to have_received(:start)
                .with('newhost',80).twice
                expect(httprequests.map &:path)
                .to end_with('/newpath?param','/newpath?param' )
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
                let(:do_request) { swarmhttp.send *args}
            end
        end
    end
    context 'lifepoints' do
        before :each do
            expect(Net::HTTPRedirection).to receive(:===)
            .with(httpresponse).and_return(true, false)
            allow(httpresponse).to receive(:[])
            .with('location') { 'http://newhost/newpath?param' }
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
            before :each do
            end
            subject { swarmhttp.present? 'objectname' }
            context 'when the object does not exist' do
                before :each do
                    expect(Net::HTTPSuccess).to receive(:===)
                    .with(httpresponse).and_return(false)
                end
                it { is_expected.to be false }
            end
            context 'when the object exists' do
                before :each do
                    expect(Net::HTTPSuccess).to receive(:===)
                    .with(httpresponse).and_return(true)
                end
                context 'without a lifepoint' do
                    before :each do
                        allow(httpresponse).to receive(:[])
                        .with('lifepoint') { nil }
                    end
                    it { is_expected.to be true }
                end
                context 'with a delete lifepoint' do
                    before :each do
                        allow(httpresponse).to receive(:[])
                        .with('lifepoint')
                        .and_return "[Wed, 29 Jun 2016 13:30:39 GMT] reps:16:4 deletable=True, [] delete"
                    end
                    it { is_expected.to be 14400 }
                end
                context 'with a non-delete lifepoint' do
                    before :each do
                        allow(httpresponse).to receive(:[])
                        .with('lifepoint')
                        .and_return "[Wed, 29 Jun 2016 13:30:39 GMT] reps:16:4 deletable=True, [] reps:2"
                    end
                    it { is_expected.to be true }
                end
                context 'with mutliple lifepoints' do
                    before :each do
                        allow(httpresponse).to receive(:[])
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
