require_relative '../swarmbucket'

describe Net::HTTPGenericRequest do
    let(:host) {'example.org'}
    let(:uri) { URI "http://#{host}/path" }

    let(:newhost) {'example.com'}
    let(:newuri) { URI "https://#{newhost}/redirected" }

    before :each do
        @request = Net::HTTP::Get.new uri
        @request['someheader'] = 'somevalue'
    end

    it 'defines an append class' do
        expect(Net::HTTP::Append.class).to be Class
    end

    context '#uri=' do
        it 'updates the uri' do
            expect { @request.uri = newuri }.to change { @request.uri }
            .from(uri)
            .to(newuri)
        end
        it 'updates the path' do
            expect { @request.uri = newuri }.to change { @request.path }
            .from('/path')
            .to('/redirected')
        end
        it 'updates the host header' do
            expect { @request.uri = newuri }.to change { @request['Host'] }
            .from('example.org')
            .to('example.com')
        end
    end

    context '#set behaves correctly, by' do

        before :each do
            @request.uri = newuri
        end

        it 'not changing random headers' do
            expect(@request['someheader']).to eq 'somevalue'
        end
        it 'duplicating the given uri' do
            expect(@request.uri).not_to be newuri
            expect(@request.uri).to eq newuri
        end
    end

    context '#uri= error handling' do
        it "fails when uri is not URI" do
            expect{@request.uri='https://example.com/redirected'}
            .to raise_error(ArgumentError)
        end
    end

end
