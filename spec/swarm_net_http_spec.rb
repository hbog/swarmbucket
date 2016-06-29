require_relative '../swarmbucket'

describe Net::HTTPGenericRequest do
    let(:request) { Net::HTTP::Get.new(URI 'http://example.org/path') }
    it 'defines an append class' do
        expect(Net::HTTP::Append.class).to be Class
    end
    context '#uri=' do
        let(:newuri) { URI 'https://example.com/redirected' }
        it 'updates the uri (host)' do
            expect { request.uri = newuri}.to change { request.uri.host }
            .from('example.org')
            .to('example.com')
        end
        it "updates the uri (request_uri)" do
            expect { request.uri = newuri}.to change { request.uri.request_uri }
            .from('/path')
            .to('/redirected')
        end
        it 'updates the host header' do
            expect { request.uri = newuri}.to change { request['Host'] }
            .from('example.org')
            .to('example.com')
        end
    end
    context '#uri= error handling' do
        it "fails when uri is not ORI" do
            expect{request.uri='https://example.com/redirected'}
            .to raise_error(ArgumentError)
        end
    end
end
