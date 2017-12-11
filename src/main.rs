extern crate rustless;
extern crate hyper;
extern crate iron;
extern crate valico;
extern crate crypto;

#[macro_use(bson, doc)]
extern crate bson;
extern crate mongodb;

use mongodb::{Client, ThreadedClient};
use mongodb::db::ThreadedDatabase;
use bson::
{
    Bson,
    Document
};

use std::fs::File;
use std::io::BufReader;
use std::io::Read;
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::
{
    Duration,
    SystemTime,
    UNIX_EPOCH
};
use crypto::digest::Digest;
use crypto::sha3::Sha3;
use valico::json_dsl;
use rustless::server::status::StatusCode;
use rustless::json::ToJson;
use rustless::
{
    Application,
    Api,
    Nesting,
    Versioning
};
use hyper::header::
{
    ContentDisposition,
    DispositionType,
    DispositionParam,
    Charset
};

fn is_atom(repository:&str, category:&str, package:&str, version:&str) -> bool
{
    let output = Command::new("equery").arg("w")
        .arg(format!("{}/{}-{}::{}", category, package, version, repository)).output().unwrap();
    let ex = format!("{}/{}/{}/{}-{}.ebuild\n", repository, category, package, package, version);
    return output.status.success() && output.stdout.ends_with(ex.as_bytes());
}

#[test]
fn test_is_atom()
{
    assert_eq!(false, is_atom("test","test","test","test"));
    assert_eq!(true, is_atom("gentoo","app-editors","vim","8.0.1298"));
}

fn main()
{
    let client = Client::connect("localhost", 27017)
        .expect("Failed to initialize standalone client.");
    let coll = client.db("gbs").collection("builds");

    let api = Api::build(|api|
    {
        api.prefix("api");
        api.version("1", Versioning::Path);

        api.namespace("atoms/:repositories/:categories/:packages/:versions", |atoms_ns|
        {
            atoms_ns.params(|params|
            {
                params.req_typed("repositories", json_dsl::string());
                params.req_typed("categories", json_dsl::string());
                params.req_typed("packages", json_dsl::string());
                params.req_typed("versions", json_dsl::string());
            });
            atoms_ns.get("builds", |endpoint|
            {
                endpoint.handle(|client, params|
                {
                    return client.json(&params.to_json());
                })
            });
            atoms_ns.get("builds/:id/status", |endpoint|
            {
                endpoint.handle(|mut client, params|
                {
                    let repository = params.find("repositories").unwrap().to_string().trim_matches('"').to_string();
                    let category = params.find("categories").unwrap().to_string().trim_matches('"').to_string();
                    let package = params.find("packages").unwrap().to_string().trim_matches('"').to_string();
                    let version = params.find("versions").unwrap().to_string().trim_matches('"').to_string();
                    // TODO check [0-0a-f]
                    let id = params.find("id").unwrap().to_string().trim_matches('"').to_string();

                    if is_atom(&repository, &category, &package, &version)
                    {
                        let s = format!("{}/{}/{}/{}/{}/status", repository, category, package, version, id);
                        let path = Path::new(&s);
                        if path.is_file()
                        {
                            let f = File::open(&s).unwrap();
                            let mut reader = BufReader::new(f);
                            let mut buf = String::new();
                            reader.read_to_string(&mut buf);
                            return client.text(buf);
                        }
                    }
                    client.set_status(StatusCode::NotFound);
                    return client.empty();
                })
            });
            atoms_ns.get("builds/:id/log", |endpoint|
            {
                endpoint.params(|params|
                {
                    params.req_typed("id", json_dsl::string());
                });
                endpoint.handle(|mut client, params|
                {
                    let repository = params.find("repositories").unwrap().to_string().trim_matches('"').to_string();
                    let category = params.find("categories").unwrap().to_string().trim_matches('"').to_string();
                    let package = params.find("packages").unwrap().to_string().trim_matches('"').to_string();
                    let version = params.find("versions").unwrap().to_string().trim_matches('"').to_string();
                    // TODO check [0-0a-f]
                    let id = params.find("id").unwrap().to_string().trim_matches('"').to_string();

                    if is_atom(&repository, &category, &package, &version)
                    {
                        let s = format!("{}/{}/{}/{}/{}/log", repository, category, package, version, id);
                        let path = Path::new(&s);
                        if path.is_file()
                        {
                            let f = File::open(&s).unwrap();
                            let mut reader = BufReader::new(f);
                            let mut buf = String::new();
                            reader.read_to_string(&mut buf);
                            return client.text(buf);
                        }
                    }
                    client.set_status(StatusCode::NotFound);
                    return client.empty();
                })
            });
            atoms_ns.get("builds/:id", |endpoint|
            {
                endpoint.params(|params|
                {
                    params.req_typed("id", json_dsl::string());
                });
                endpoint.handle(|mut client, params|
                {
                    let repository = params.find("repositories").unwrap().to_string().trim_matches('"').to_string();
                    let category = params.find("categories").unwrap().to_string().trim_matches('"').to_string();
                    let package = params.find("packages").unwrap().to_string().trim_matches('"').to_string();
                    let version = params.find("versions").unwrap().to_string().trim_matches('"').to_string();
                    // TODO check [0-0a-f]
                    let id = params.find("id").unwrap().to_string().trim_matches('"').to_string();

                    if is_atom(&repository, &category, &package, &version)
                    {
                        let s = format!("{}/{}/{}/{}/{}/{2}-{3}.tbz2", repository, category, package, version, id);
                        let path = Path::new(&s);
                        if path.is_file()
                        {
                            client.set_header(ContentDisposition
                            {
                              disposition: DispositionType::Attachment,
                              parameters: vec![DispositionParam::Filename(
                                Charset::Us_Ascii,
                                None,
                                format!("{}-{}.tbz2", package, version).into_bytes()
                            )]});
                            return client.file(path);
                        }
                    }
                    client.set_status(StatusCode::NotFound);
                    return client.empty();
                })
            });
            atoms_ns.post("builds", |endpoint|
            {
                endpoint.handle(move |mut client, params|
                {
                    let repository = params.find("repositories").unwrap().to_string().trim_matches('"').to_string();
                    let category = params.find("categories").unwrap().to_string().trim_matches('"').to_string();
                    let package = params.find("packages").unwrap().to_string().trim_matches('"').to_string();
                    let version = params.find("versions").unwrap().to_string().trim_matches('"').to_string();

                    let mut uses = String::new();
                    let use_flag = params.find("use").unwrap();
                    for (key, value) in use_flag.as_object().unwrap().iter()
                    {
                        uses.push_str(&format!("{}{} ", match value.as_bool().unwrap(){true => "", false => "-"}, key));
                    }
                    println!("{}", params);
                    println!("{}", uses);

                    let mut hasher = Sha3::sha3_256();
                    hasher.input_str(&format!("{}{}{}{}{}", repository, category, package, version, uses));
                    let id = hasher.result_str();

                    let url = format!("{}/{}/{}/{}/builds/{}", repository, category, package, version, id);

                    if is_atom(&repository, &category, &package, &version)
                    {
                        if !Path::new(&format!("{}/{}/{}/{}/{}/{2}-{3}.tbz2", repository, category, package, version, id)).exists()
                        {
                            {
                                let mut uses = Document::new();
                                for (key, value) in use_flag.as_object().unwrap().iter()
                                {
                                    uses.insert(key.clone(), Bson::Boolean(value.as_bool().unwrap().clone()));
                                }
                                let s = SystemTime::now();
                                let doc = doc!
                                {
                                    "date" => &format!("{}", s.duration_since(UNIX_EPOCH).unwrap().as_secs()),
                                    "id" => id.clone(),
                                    "repository" => repository.clone(),
                                    "category" => category.clone(),
                                    "package" => package.clone(),
                                    "version" => version.clone(),
                                    "use" => uses
                                };
                                coll.insert_one(doc.clone(), None).ok().expect("Failed to insert document.");
                            }
                            thread::spawn(||
                            {
                                let b = Command::new("./buildreq.sh")
                                .arg(repository)
                                .arg(category)
                                .arg(package)
                                .arg(version)
                                .arg(id)
                                .arg(uses)
                                .output().unwrap();
                                println!("{}\n", String::from_utf8_lossy(&b.stdout));
                                println!("{}\n", String::from_utf8_lossy(&b.stderr));
                            });
                        }
                        return client.text(url);
                    }
                    else
                    {
                        client.set_status(StatusCode::NotFound);
                        return client.empty();
                    }
                })
            });
        });
    });

    let app = Application::new(api);

    iron::Iron::new(app).http("0.0.0.0:4000").unwrap();
}
